defmodule DawarichWeb.FamilyPagesTest do
  use Dawarich.JobsCase, async: false

  import Dawarich.Test.FormIsolation
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

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

  test "native Family owner and member controls retain policy and inactive refusal", ctx do
    Repo.query!(
      "UPDATE family_invitations SET expires_at=$1 WHERE token=$2",
      [
        DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.to_naive(),
        "a9fpl-pending"
      ],
      log: false
    )

    owner = document(ctx.owner, "/family")
    assert_form_isolated(document(ctx.owner, "/family/invitations"))
    assert_form_isolated(document(ctx.member, "/family/location_requests/94001"))
    assert String.contains?(owner, "Leipzig Fixture Family")
    expect_element(owner, "a[href='/family/edit']")

    expect_element(
      owner,
      "[data-native-family-action=remove_member][data-native-family-target='92002']"
    )

    expect_element(
      owner,
      "#native-family-invite[phx-submit='family:invite'] input[name='family_invitation[email]']"
    )

    expect_element(
      owner,
      "#native-family-sharing[phx-hook=FamilySharing][data-native-sharing-event='family:sharing']"
    )

    expect_element(
      owner,
      "[data-native-family-action=cancel_invitation][data-native-family-target='93001']"
    )

    member = document(ctx.member, "/family?locale=de")
    expect_element(member, "a[href='/family/edit']", false)
    expect_element(member, "#native-family-invite", false)

    expect_element(
      member,
      "[data-native-family-action=remove_member][data-native-family-target='92002']"
    )

    expect_element(
      member,
      "form[action='/family/location_requests?target_user_id=90101'][phx-submit*='family:request']"
    )

    for html <- [owner, member],
        marker <- ~w(data-lat= a9fpl-fixture- data-controller data-action turbo-frame),
        do: refute(String.contains?(html, marker))

    Repo.query!("UPDATE users SET status = 0 WHERE id = $1", [ctx.owner.id])
    refused = document(ctx.owner, "/family")
    expect_element(refused, "#family-shell", false)
    expect_element(refused, "[role=alert]")
    assert Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows == [[0]]
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

  test "native family documents ignore compatibility keys without Rails replay", ctx do
    saved = Application.get_env(:dawarich, :rails_routes, [])
    upstream = Dawarich.Test.RailsFormRequests.upstream!()
    Application.put_env(:dawarich, :rails_routes, ["family"])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, saved) end)

    for {user, path} <- [
          {ctx.owner, "/family"},
          {ctx.outsider, "/family/new"},
          {ctx.owner, "/family/edit"}
        ] do
      conn = RailsUser.signed_in(user.id) |> freeze_clock() |> get(path)
      assert conn.status == 200
      assert conn.resp_body =~ "/native/app"
      assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 0)
    end
  end

  test "retired family UI writes have no routes even with compatibility keys" do
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
      assert :error =
               Phoenix.Router.route_info(DawarichWeb.Router, method, path, "www.example.com")

      refute Map.has_key?(
               Phoenix.Router.route_info(DawarichWeb.Router, "GET", "/family", "www.example.com"),
               :rails_gate
             )
    end

    assert Phoenix.Router.route_info(
             DawarichWeb.Router,
             "POST",
             "/family/members",
             "www.example.com"
           ) == :error
  end
end
