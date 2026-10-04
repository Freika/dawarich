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

    Repo.query!(
      "UPDATE family_invitations SET expires_at = $1 WHERE token IN ('a9fpl-pending', 'a9fpl-accepted', 'a9fpl-cancelled')",
      [NaiveDateTime.add(NaiveDateTime.utc_now(), 86_400)]
    )

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

  test "signed out invitation offers existing registration and sign in paths" do
    html =
      build_conn()
      |> freeze_clock()
      |> get("/invitations/a9fpl-pending?locale=de")
      |> html_response(200)

    assert element?(html, "a[href='/users/sign_up?invitation_token=a9fpl-pending']")
    assert element?(html, "a[href='/users/sign_in?invitation_token=a9fpl-pending']")
    refute element?(html, "a[data-method='post']")
    refute html =~ "a9fpl-fixture-"
    refute html =~ "a-member@a9fpl.dawarich.test"
  end

  test "accept control preserves Rails signed in behavior and keeps Rails endpoint", ctx do
    for user <- [ctx.invitee, ctx.owner] do
      html =
        RailsUser.signed_in(user.id)
        |> freeze_clock()
        |> get("/invitations/a9fpl-pending")
        |> html_response(200)

      assert element?(
               html,
               "a[href='/family/memberships?token=a9fpl-pending'][data-method='post']"
             )

      assert element?(html, "a[href='/users/sign_out'][data-method='delete']")
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
    refute element?(html, "a[data-method='post']")

    assert Phoenix.Router.route_info(
             DawarichWeb.Router,
             "POST",
             "/family/memberships",
             "www.example.com"
           ) == :error
  end

  test "invitation key hands back public and nested token landings" do
    saved_routes = Application.get_env(:dawarich, :rails_routes, [])
    saved_upstream = Application.get_env(:dawarich, :rails_upstream)
    upstream = listen()

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_routes, saved_routes)
      Application.put_env(:dawarich, :rails_upstream, saved_upstream)
      :gen_tcp.close(upstream.listen)
    end)

    Application.put_env(:dawarich, :rails_routes, ["family"])
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    for path <- ~w(/invitations/a9fpl-pending /family/invitations/a9fpl-pending) do
      response = Task.async(fn -> build_conn() |> freeze_clock() |> get(path) end)
      socket = accept(upstream)
      {head, _rest} = read_head(socket)
      assert request_line(head) == "GET #{path} HTTP/1.1"
      reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
      conn = Task.await(response)
      assert conn.resp_body == "rails"
      refute Map.has_key?(conn.private, :phoenix_router)
      :gen_tcp.close(socket)
    end
  end

  test "request document belongs only to its target and submits Rails accept decline", ctx do
    Repo.query!("UPDATE family_location_requests SET expires_at = $1 WHERE id = 94001", [
      DateTime.add(@now, 3600) |> DateTime.to_naive()
    ])

    html =
      RailsUser.signed_in(ctx.member.id)
      |> freeze_clock()
      |> get("/family/location_requests/94001")
      |> html_response(200)

    for action <- ~w(accept decline) do
      assert element?(
               html,
               "form[action='/family/location_requests/94001/#{action}'] input[name='_method'][value='patch']"
             )
    end

    assert element?(html, "select[name='duration'] option[value='24h'][selected]")

    foreign =
      RailsUser.signed_in(ctx.owner.id)
      |> freeze_clock()
      |> get("/family/location_requests/94001")

    assert foreign.status == 302
    assert redirected_to(foreign) == "http://www.example.com/family"

    expired =
      RailsUser.signed_in(ctx.member.id)
      |> freeze_clock()
      |> get("/family/location_requests/94002")
      |> html_response(200)

    assert element?(expired, ".badge-error")
    refute element?(expired, "form[action^='/family/location_requests/']")

    index =
      RailsUser.signed_in(ctx.owner.id)
      |> freeze_clock()
      |> get("/family/invitations")
      |> html_response(200)

    assert element?(
             index,
             "a[href='/family/invitations/a9fpl-pending'][data-turbo-method='delete']"
           )

    member_index =
      RailsUser.signed_in(ctx.member.id)
      |> freeze_clock()
      |> get("/family/invitations")
      |> html_response(200)

    refute element?(member_index, "a[data-turbo-method='delete'][href^='/family/invitations/']")
  end
end
