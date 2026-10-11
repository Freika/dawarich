defmodule DawarichWeb.FamilyInvitationTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Dawarich.Test.RawHTTP

  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{FrameSeeds, RailsUser}

  @external_resource "test/fixtures/family_pages/owner_en.json"
  @now FrameSeeds.load_family("owner_en")["now"] |> DateTime.from_iso8601() |> elem(1)
  @endpoint DawarichWeb.Endpoint

  defp freeze_clock(conn), do: Plug.Conn.assign(conn, :now, @now)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("owner_en"))
    %{owner: owner, member: Accounts.get(90102), invitee: Accounts.get(90103)}
  end

  defp element?(html, selector),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> Enum.any?()

  test "public invitation distinguishes pending expired processed and missing token" do
    pending = build_conn() |> freeze_clock() |> get("/invitations/a9fpl-pending")
    assert pending.status == 200
    assert element?(pending.resp_body, "h1")

    for {token, message} <- [
          {"a9fpl-past", "this_invitation_has_expired"},
          {"a9fpl-cancelled", "this_invitation_is_no_longer_valid"},
          {"a9fpl-accepted", "this_invitation_is_no_longer_valid"}
        ] do
      conn = build_conn() |> freeze_clock() |> get("/invitations/" <> token)
      assert conn.status == 302
      assert redirected_to(conn) == "http://www.example.com/"

      assert conn.private.dawarich_rails_session_changes["flash"]["flashes"]["alert"] ==
               DawarichWeb.Translate.t("en", "controllers.family.invitations." <> message, %{})
    end

    assert_raise DawarichWeb.NotFoundError, fn ->
      build_conn() |> freeze_clock() |> get("/invitations/missing-a9fpl")
    end
  end

  test "unsupported invitation settings refuse locally without an upstream request", ctx do
    upstream = listen()
    previous = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, previous)
      :gen_tcp.close(upstream.listen)
    end)

    Repo.query!("UPDATE users SET settings=$1 WHERE id=$2", [%{"timezone" => []}, ctx.invitee.id],
      log: false
    )

    for path <- ["/invitations/a9fpl-pending", "/family/invitations/a9fpl-pending"] do
      server =
        Task.async(fn ->
          case :gen_tcp.accept(upstream.listen, 500) do
            {:ok, socket} ->
              read_head(socket)
              reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
              :gen_tcp.close(socket)
              :upstream_request

            {:error, :timeout} ->
              :no_upstream_request
          end
        end)

      conn = RailsUser.signed_in(ctx.invitee.id) |> freeze_clock() |> get(path)
      upstream_result = Task.await(server)
      assert conn.status == 422
      assert upstream_result == :no_upstream_request
      route = Phoenix.Router.route_info(DawarichWeb.Router, "GET", path, "www.example.com")
      refute Map.has_key?(route[:metadata] || %{}, :rails_gate)
    end

    assert {:error, :invalid_input} =
             DawarichWeb.FamilyInvitationPage.read("a9fpl-pending", Accounts.get(ctx.invitee.id),
               now: @now
             )
  end

  test "signed out invitation offers existing registration and sign in paths" do
    html =
      build_conn()
      |> freeze_clock()
      |> get("/invitations/a9fpl-pending?locale=de")
      |> html_response(200)

    assert element?(html, "a[href='/users/sign_up?invitation_token=a9fpl-pending']")
    assert element?(html, "a[href='/users/sign_in?invitation_token=a9fpl-pending']")
    refute element?(html, "form[action='/family/memberships']")
    refute html =~ "a9fpl-fixture-"
    refute html =~ "a-member@a9fpl.dawarich.test"
  end

  test "public invitation offers ordinary CSRF acceptance and scoped durable command", ctx do
    for user <- [ctx.invitee, ctx.owner] do
      html =
        RailsUser.signed_in(user.id)
        |> freeze_clock()
        |> get("/invitations/a9fpl-pending")
        |> html_response(200)

      assert element?(
               html,
               "form[action='/family/memberships'][method='post'] input[name='token'][value='a9fpl-pending']"
             )

      assert element?(
               html,
               "form[action='/users/sign_out'] input[name='_method'][value='delete']"
             )

      assert element?(html, "form[action='/family/memberships'] input[name='authenticity_token']")
      refute html =~ "data-method="
      assert html =~ "/native/app.js"
    end

    System.put_env("SELF_HOSTED", "false")
    System.put_env("JWT_SECRET_KEY", "test")
    on_exit(fn -> for key <- ~w(SELF_HOSTED JWT_SECRET_KEY), do: System.delete_env(key) end)

    Repo.query!("UPDATE families SET access_until = $1 WHERE id = 91001", [
      DateTime.add(@now, -1) |> DateTime.to_naive()
    ])

    html =
      RailsUser.signed_in(ctx.invitee.id)
      |> freeze_clock()
      |> get("/invitations/a9fpl-pending")
      |> html_response(200)

    assert element?(html, ".alert-warning")
    refute element?(html, "form[action='/family/memberships']")

    assert %{plug: DawarichWeb.FamilyInvitationAcceptance} =
             Phoenix.Router.route_info(
               DawarichWeb.Router,
               "POST",
               "/family/memberships",
               "www.example.com"
             )

    System.put_env("SELF_HOSTED", "true")

    conn =
      Dawarich.Test.FamilyCorpus.request(ctx.invitee, "POST", "/family/memberships", %{
        "token" => "a9fpl-pending"
      })

    assert conn.status == 302

    assert Repo.query!(
             "SELECT count(*) FROM family_memberships WHERE user_id=$1",
             [ctx.invitee.id],
             log: false
           ).rows == [[1]]

    assert Repo.query!(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Families.EventsWorker' AND args->>'user_id'=$1",
             [Integer.to_string(ctx.invitee.id)],
             log: false
           ).rows == [[1]]
  end

  test "native invitation landings ignore compatibility keys without Rails replay" do
    saved = Application.get_env(:dawarich, :rails_routes, [])
    upstream = Dawarich.Test.RailsFormRequests.upstream!()
    Application.put_env(:dawarich, :rails_routes, ["family"])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, saved) end)

    for path <- ~w(/invitations/a9fpl-pending /family/invitations/a9fpl-pending) do
      response = build_conn() |> freeze_clock() |> get(path)
      assert response.status == 200
      assert response.resp_body =~ "/native/app"
      assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 0)
    end
  end

  test "native request document belongs only to its target and submits accept decline", ctx do
    Repo.query!("UPDATE family_location_requests SET expires_at = $1 WHERE id = 94001", [
      DateTime.add(DateTime.utc_now(), 3600) |> DateTime.to_naive()
    ])

    html =
      RailsUser.signed_in(ctx.member.id)
      |> freeze_clock()
      |> get("/family/location_requests/94001")
      |> html_response(200)

    assert element?(
             html,
             "#native-family-request[phx-submit='family_respond'] input[name='decision'][value='accept']"
           )

    assert element?(html, "button[phx-click='family_respond'][phx-value-decision='decline']")

    assert element?(html, "select[name='duration'] option[value='24h'][selected]")

    foreign =
      RailsUser.signed_in(ctx.owner.id)
      |> freeze_clock()
      |> get("/family/location_requests/94001")

    assert foreign.status == 302
    assert redirected_to(foreign) == "/family"

    expired =
      RailsUser.signed_in(ctx.member.id)
      |> freeze_clock()
      |> get("/family/location_requests/94002")
      |> html_response(200)

    assert element?(expired, "[data-request-status=expired]")
    refute element?(expired, "form[action^='/family/location_requests/']")

    Repo.query!("UPDATE family_invitations SET expires_at='3026-01-01' WHERE status=0", [],
      log: false
    )

    index =
      RailsUser.signed_in(ctx.owner.id)
      |> freeze_clock()
      |> get("/family/invitations")
      |> html_response(200)

    assert element?(
             index,
             "[data-invitation-id] button[phx-click]"
           )

    member_index =
      RailsUser.signed_in(ctx.member.id)
      |> freeze_clock()
      |> get("/family/invitations")
      |> html_response(200)

    refute element?(member_index, "[data-invitation-id] button[phx-click]")
  end

  test "debug SQL logs from the invitation landing never carry the invitation token" do
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)

    log =
      ExUnit.CaptureLog.capture_log([level: :debug], fn ->
        assert build_conn()
               |> freeze_clock()
               |> get("/invitations/a9fpl-pending")
               |> Map.get(:status) ==
                 200

        Logger.flush()
      end)

    assert log =~ "WHERE i.token = $1"
    refute log =~ ~s("a9fpl-pending")
  end
end
