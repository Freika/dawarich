defmodule DawarichWeb.FamilyPagesTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]
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

    Repo.query!("UPDATE family_invitations SET expires_at='3026-01-01' WHERE status=0", [],
      log: false
    )

    %{owner: owner, member: Accounts.get(90102), outsider: Accounts.get(90103)}
  end

  defp document(user, path),
    do: RailsUser.signed_in(user.id) |> freeze_clock() |> get(path) |> html_response(200)

  defp expect_element(html, selector, expected \\ true) do
    found = html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> Enum.any?()
    assert found == expected, selector
  end

  test "native owner and member controls preserve roles and exclude embedded locations", ctx do
    owner = document(ctx.owner, "/family")
    assert owner =~ "Leipzig Fixture Family"
    expect_element(owner, "a[href='/family/edit']")
    expect_element(owner, "#native-invite-form input[name='family_invitation[email]']")
    expect_element(owner, "#native-family-sharing[phx-change='family_set_sharing']")
    expect_element(owner, "[data-invitation-id]")
    member = document(ctx.member, "/family?locale=de")
    expect_element(member, "a[href='/family/edit']", false)
    expect_element(member, "#native-invite-form", false)
    expect_element(member, "button[phx-value-target_user_id='90101']")
    refute owner =~ "data-lat="
    refute owner =~ "a9fpl-fixture-"
    refute owner =~ "a9fpl-pending"
    Repo.query!("UPDATE users SET status = 0 WHERE id = $1", [ctx.owner.id])
    assert document(ctx.owner, "/family") =~ "/native/app"
  end

  test "native create upgrade and lapsed branches preserve actions and HTTP upgrade payload",
       ctx do
    create = document(ctx.outsider, "/family/new")

    expect_element(
      create,
      "#native-family-form[phx-submit='family_save'] input[name='family[name]']"
    )

    saved = Map.new(~w(SELF_HOSTED JWT_SECRET_KEY), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "false")
    System.put_env("JWT_SECRET_KEY", "test")

    on_exit(fn ->
      for {key, value} <- saved,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    upgrade = document(ctx.outsider, "/family/new?locale=de")

    expect_element(
      upgrade,
      "a[href='/native/family/upgrade'][target='_blank'][rel='noopener noreferrer']"
    )

    expect_element(upgrade, "#native-family-form", false)
    conn = RailsUser.signed_in(ctx.outsider.id) |> get("/native/family/upgrade")
    params = redirected_to(conn) |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    [_head, body, _signature] = String.split(params["token"], ".")
    payload = body |> Base.url_decode64!(padding: false) |> Jason.decode!()
    assert payload["plan"] == "family"
    assert payload["interval"] == "annual"
    assert params["utm_campaign"] == "family_upgrade"

    Repo.query!("UPDATE families SET access_until = $1 WHERE id = 91001", [
      DateTime.add(@now, -1) |> DateTime.to_naive()
    ])

    Repo.query!("UPDATE users SET plan = 1 WHERE id = $1", [ctx.owner.id])
    lapsed = document(ctx.owner, "/family/new")
    expect_element(lapsed, "#native-family-sharing")
    expect_element(lapsed, "button[phx-click]")
    member = document(ctx.member, "/family/new")
    expect_element(member, "#native-family-sharing")
    expect_element(member, "a[href='/native/family/upgrade']", false)
  end

  test "native edit retains the name and refuses members to its own safe destination", ctx do
    edit = document(ctx.owner, "/family/edit")
    expect_element(edit, "#native-family-form[phx-submit='family_save']")
    expect_element(edit, "input[name='family[name]'][value='Leipzig Fixture Family']")
    expect_element(edit, "button[phx-click]")

    for referer <- [
          "http://user@www.example.com/return?x=1",
          "//www.example.com/family",
          "/family?tab=members",
          "https://www.example.com/family"
        ] do
      conn =
        RailsUser.signed_in(ctx.member.id)
        |> put_req_header("referer", referer)
        |> get("/family/edit")

      assert conn.status == 302
      assert redirected_to(conn) == "/"
    end
  end

  test "family key hands back documents before pipeline", ctx do
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

    for path <- ~w(/family /family/new /family/edit) do
      response =
        Task.async(fn -> RailsUser.signed_in(ctx.owner.id) |> freeze_clock() |> get(path) end)

      socket = accept(upstream)
      {head, _rest} = read_head(socket)
      assert request_line(head) == "GET #{path} HTTP/1.1"
      reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
      conn = Task.await(response)
      assert conn.resp_body == "rails"
      refute Map.has_key?(conn.private, :phoenix_router)
      refute Map.has_key?(conn.assigns, :current_user)
      :gen_tcp.close(socket)
    end
  end

  test "family writes have native routes and retain explicit handback" do
    saved = Application.get_env(:dawarich, :rails_routes, [])
    Application.put_env(:dawarich, :rails_routes, ["family"])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, saved) end)

    for {method, path} <- [
          {"POST", "/family"},
          {"PATCH", "/family"},
          {"PUT", "/family"},
          {"DELETE", "/family"},
          {"POST", "/family/invitations"},
          {"POST", "/family/invitations.91001"},
          {"DELETE", "/family/invitations/a9fpl-pending"},
          {"DELETE", "/family/members/92002"},
          {"POST", "/family/location_requests"},
          {"PATCH", "/family/location_requests/94001/accept"},
          {"PATCH", "/family/location_requests/94001/decline"},
          {"PATCH", "/family/location_sharing"}
        ] do
      assert %{plug: DawarichWeb.FamilyFormRoutes} =
               Phoenix.Router.route_info(DawarichWeb.Router, method, path, "www.example.com")

      assert DawarichWeb.Strangler.handed_back?(["family"])
    end

    assert Phoenix.Router.route_info(
             DawarichWeb.Router,
             "POST",
             "/family/members",
             "www.example.com"
           ) == :error
  end
end
