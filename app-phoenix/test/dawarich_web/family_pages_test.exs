defmodule DawarichWeb.FamilyPagesTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]
  import Dawarich.Test.RawHTTP

  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{FrameSeeds, RailsUser}

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("owner_en"))

    Repo.query!("UPDATE family_invitations SET expires_at = $1 WHERE token = 'a9fpl-pending'", [
      NaiveDateTime.add(NaiveDateTime.utc_now(), 86_400)
    ])

    %{owner: owner, member: Accounts.get(90102), outsider: Accounts.get(90103)}
  end

  defp document(user, path), do: RailsUser.signed_in(user.id) |> get(path) |> html_response(200)

  defp expect_element(html, selector, expected \\ true) do
    found = html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> Enum.any?()
    assert found == expected, selector
  end

  test "show renders owner and member Rails controls", ctx do
    html = document(ctx.owner, "/family")
    owner = html
    assert true == (html =~ "Leipzig Fixture Family")
    expect_element(owner, "a[href='/family/edit']")

    expect_element(
      owner,
      "a[href='/family/members/92002'][data-turbo-method='delete'][data-turbo-confirm]"
    )

    expect_element(
      owner,
      "form[action='/family/invitations.91001'] input[name='family_invitation[email]']"
    )

    expect_element(
      owner,
      "form[action='/family/location_sharing'] input[name='_method'][value='patch']"
    )

    expect_element(
      owner,
      "form[action='/family/invitations/a9fpl-pending'] input[name='_method'][value='delete']"
    )

    member = document(ctx.member, "/family?locale=de")
    expect_element(member, "a[href='/family/edit']", false)
    expect_element(member, "form[action='/family/invitations.91001']", false)
    expect_element(member, "a[href='/family/members/92002'][data-turbo-method='delete']")
    expect_element(member, "form[action='/family/location_requests?target_user_id=90101']")
    assert false == (html =~ "data-lat=")
    assert false == (html =~ "a9fpl-fixture-")
    Repo.query!("UPDATE users SET status = 0 WHERE id = $1", [ctx.owner.id])
    trial = document(ctx.owner, "/family")
    expect_element(trial, "#family-getting-started .text-xs.text-base-content\\/60.mt-3")
  end

  test "new renders create upgrade and lapsed branches", ctx do
    create = document(ctx.outsider, "/family/new")
    expect_element(create, "form[action='/family'] input[name='family[name]']")
    System.put_env("SELF_HOSTED", "false")
    System.put_env("JWT_SECRET_KEY", "test")
    on_exit(fn -> for key <- ~w(SELF_HOSTED JWT_SECRET_KEY), do: System.delete_env(key) end)
    upgrade = document(ctx.outsider, "/family/new?locale=de")
    expect_element(upgrade, "a.btn.btn-primary[target='_blank'][rel='noopener noreferrer']")
    expect_element(upgrade, "form[action='/family']", false)

    [href] =
      upgrade
      |> LazyHTML.from_document()
      |> LazyHTML.query("a.btn.btn-primary[target='_blank']")
      |> LazyHTML.attribute("href")

    params = href |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    [_head, body, _signature] = String.split(params["token"], ".")
    payload = body |> Base.url_decode64!(padding: false) |> Jason.decode!()
    assert payload["plan"] == "family"
    assert payload["interval"] == "annual"
    assert params["utm_campaign"] == "family_upgrade"

    Repo.query!("UPDATE families SET access_until = $1 WHERE id = 91001", [
      ~N[2026-10-03 09:59:59]
    ])

    Repo.query!("UPDATE users SET plan = 1 WHERE id = $1", [ctx.owner.id])
    lapsed = document(ctx.owner, "/family/new")
    expect_element(lapsed, "a[href='/family/members/92002'][data-turbo-method='delete']")
    expect_element(lapsed, "form[action='/family/location_sharing']")
    member = document(ctx.member, "/family/new")
    expect_element(member, "a[href='/family/members/92002'][data-turbo-method='delete']")
    expect_element(member, "a.btn.btn-primary[target='_blank']", false)
  end

  test "edit preserves owner policy and Rails form verb", ctx do
    edit = document(ctx.owner, "/family/edit")
    expect_element(edit, "form[action='/family.91001'] input[name='_method'][value='patch']")
    expect_element(edit, "input[name='family[name]'][value='Leipzig Fixture Family']")
    expect_element(edit, "a[href='/family'][data-turbo-method='delete'][data-turbo-confirm]")
    conn = RailsUser.signed_in(ctx.member.id) |> get("/family/edit")
    assert conn.status == 303
    assert redirected_to(conn, 303) == "http://www.example.com/"

    assert conn.private.dawarich_rails_session_changes["flash"]["flashes"]["alert"] ==
             DawarichWeb.Translate.t(
               "en",
               "controllers.application.you_are_not_authorized_to_perform_this_action",
               %{}
             )

    returned =
      RailsUser.signed_in(ctx.member.id)
      |> put_req_header("referer", "http://www.example.com/family")
      |> get("/family/edit")

    assert redirected_to(returned, 303) == "http://www.example.com/family"
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
      response = Task.async(fn -> RailsUser.signed_in(ctx.owner.id) |> get(path) end)
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

  test "all family writes still reach Rails" do
    for {method, path} <- [
          {"POST", "/family"},
          {"PATCH", "/family"},
          {"PUT", "/family"},
          {"DELETE", "/family"},
          {"POST", "/family/invitations"},
          {"POST", "/family/invitations.91001"},
          {"DELETE", "/family/invitations/a9fpl-pending"},
          {"DELETE", "/family/members/92002"},
          {"POST", "/family/members"},
          {"POST", "/family/location_requests"},
          {"PATCH", "/family/location_requests/94001/accept"},
          {"PATCH", "/family/location_requests/94001/decline"},
          {"PATCH", "/family/location_sharing"}
        ] do
      assert Phoenix.Router.route_info(DawarichWeb.Router, method, path, "www.example.com") ==
               :error
    end
  end
end
