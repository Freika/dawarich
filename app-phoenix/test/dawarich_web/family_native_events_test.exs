defmodule DawarichWeb.FamilyNativeEventsTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  @endpoint DawarichWeb.Endpoint

  setup do
    Code.ensure_loaded!(Dawarich.Accounts.User)
    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("owner_en"))

    Repo.query!("UPDATE family_invitations SET expires_at='3026-01-01' WHERE status=0", [],
      log: false
    )

    Repo.query!("UPDATE family_location_requests SET expires_at='3026-01-01' WHERE status=0", [],
      log: false
    )

    saved = Map.new(~w(SELF_HOSTED DAWARICH_RAILS), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      for {key, value} <- saved,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    %{owner: owner, member: Accounts.get(90102), outsider: Accounts.get(90103)}
  end

  defp open(user, path) do
    {:ok, view, html} =
      live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

    assert html =~ "/native/app"
    {view, html}
  end

  defp row(sql), do: Repo.query!(sql, [], log: false).rows

  test "every family variant has a native root and excludes capabilities from socket state",
       ctx do
    for {user, path} <- [
          {ctx.owner, "/family"},
          {ctx.owner, "/family/edit"},
          {ctx.owner, "/family/invitations"},
          {ctx.outsider, "/family/new"},
          {ctx.member, "/family/location_requests/94001"}
        ] do
      {view, html} = open(user, path)
      assert Dawarich.Test.NativeAdminUI.labels(html) == []
      refute html =~ "RailsStimulus"
      refute html =~ "data-controller="
      refute html =~ "<turbo-frame"
      refute html =~ "data-turbo-method"
      refute html =~ "a9fpl-pending"
      assigns = :sys.get_state(view.pid).socket.assigns
      refute Map.has_key?(assigns.current_user, :api_key)
      refute Map.has_key?(assigns.current_scope.user, :encrypted_password)
      refute inspect(assigns.page) =~ "a9fpl-pending"
    end
  end

  test "owner and new-family forms retain validation and notices in place", ctx do
    {view, _} = open(ctx.owner, "/family/edit")
    view |> form("#native-family-form", family: %{name: ""}) |> render_submit()
    assert has_element?(view, "#family-errors li")
    assert has_element?(view, "input[name='family[name]'][value='']")
    assert row("SELECT name FROM families WHERE id=91001") == [["Leipzig Fixture Family"]]
    view |> form("#native-family-form", family: %{name: "Changed family"}) |> render_submit()
    assert_redirect(view, "/family")
    assert row("SELECT name FROM families WHERE id=91001") == [["Changed family"]]
    {new, _} = open(ctx.outsider, "/family/new")
    new |> form("#native-family-form", family: %{name: ""}) |> render_submit()
    assert has_element?(new, "#family-errors li")
    new |> form("#native-family-form", family: %{name: "New family"}) |> render_submit()
    assert_redirect(new, "/family")
    assert row("SELECT name FROM families WHERE creator_id=90103") == [["New family"]]
  end

  test "native member confirmation gates cancellation and repeated removal cannot affect the owner",
       ctx do
    {view, _} = open(ctx.owner, "/family")
    selector = "button[data-family-action=remove_member][data-family-target='92002']"
    assert has_element?(view, selector)
    assert row("SELECT count(*) FROM family_memberships WHERE id=92002") == [[1]]
    view |> element(selector) |> render_click()
    render_click(view, "family_cancel_confirm", %{})
    assert row("SELECT count(*) FROM family_memberships WHERE id=92002") == [[1]]
    view |> element(selector) |> render_click()
    render_click(view, "family_confirm", %{})
    assert row("SELECT count(*) FROM family_memberships WHERE id=92002") == [[0]]
    render_click(view, "family:member", %{"id" => "92002"})
    assert row("SELECT count(*) FROM family_memberships WHERE id=92001") == [[1]]
    assert has_element?(view, "[role=alert]")
  end

  test "native rendered member command carries its membership ID and removes only that member",
       ctx do
    {view, _} = open(ctx.owner, "/family")

    view
    |> element("button[data-family-action=remove_member][data-family-target='92002']")
    |> render_click()

    render_click(view, "family_confirm", %{})
    assert row("SELECT count(*) FROM family_memberships WHERE id=92002") == [[0]]
    assert row("SELECT count(*) FROM family_memberships WHERE id=92001") == [[1]]
  end

  test "native map family commands preserve member role refusals without hidden writes", ctx do
    {view, _} = open(ctx.member, "/family")
    refute has_element?(view, "#native-family-invite")
    refute has_element?(view, "a[href='/family/edit']")
    render_click(view, "family:destroy", %{})
    assert row("SELECT count(*) FROM families WHERE id=91001") == [[1]]
    assert has_element?(view, "[role=alert]")

    render_submit(view, "family:invite", %{
      "family_invitation" => %{"email" => "foreign@example.invalid"}
    })

    assert row("SELECT count(*) FROM family_invitations WHERE email='foreign@example.invalid'") ==
             [[0]]
  end

  test "native map invitation validation refreshes ID-only controls and cancels exactly the owned invitation",
       ctx do
    Dawarich.Jobs.Ownership.put!(Repo, "command:mail.family_invitation", :oban)
    {view, _} = open(ctx.owner, "/family")
    render_submit(view, "family:invite", %{"family_invitation" => %{"email" => ""}})
    assert has_element?(view, "[role=alert]")

    render_submit(view, "family:invite", %{
      "family_invitation" => %{"email" => "new-native@example.invalid"}
    })

    [[id]] = row("SELECT id FROM family_invitations WHERE email='new-native@example.invalid'")
    assert has_element?(view, "[data-family-action=cancel_invitation][data-family-target='#{id}']")

    refute Map.has_key?(
             Enum.find(
               :sys.get_state(view.pid).socket.assigns.page.presentation.invitations,
               &(&1.id == id)
             ),
             :token
           )

    view
    |> element("[data-family-action=cancel_invitation][data-family-target='#{id}']")
    |> render_click()

    render_click(view, "family_confirm", %{})
    assert row("SELECT status FROM family_invitations WHERE id=#{id}") == [[3]]
    refute has_element?(view, "[data-family-action=cancel_invitation][data-family-target='#{id}']")
  end

  test "native map consent history and duration persist independently and refresh the native indicator",
       ctx do
    {view, _} = open(ctx.member, "/family")

    render_change(view, "family:sharing", %{
      "sharing" => %{
        "enabled" => "1",
        "duration" => "6h",
        "share_history" => "1",
        "history_window" => "30d",
        "history_before_sharing" => "0"
      }
    })

    [[config]] = row("SELECT settings #> '{family,location_sharing}' FROM users WHERE id=90102")
    assert config["enabled"] and config["share_history"]
    refute config["history_before_sharing"]
    assert config["duration"] == "6h" and config["history_window"] == "30d"
    assert has_element?(view, "input[name='sharing[share_history]'][type=checkbox][checked]")
    assert render(view) =~ "Location sharing enabled for 6 hours"
    assert has_element?(view, "select[name='sharing[duration]'] option[value='6h'][selected]")

    render_change(view, "family:sharing", %{
      "sharing" => %{
        "enabled" => "1",
        "duration" => "1h",
        "share_history" => "0"
      }
    })

    assert has_element?(view, "input[name='sharing[enabled]'][type=checkbox][checked]")

    assert has_element?(
             view,
             "#family-navbar-indicator[data-tip='Location is being shared with your family']"
           )

    refute has_element?(view, "input[name='sharing[share_history]'][type=checkbox][checked]")
    assert has_element?(view, "select[name='sharing[duration]'] option[value='1h'][selected]")

    render_change(view, "family:sharing", %{
      "sharing" => %{"enabled" => "0", "share_history" => "1"}
    })

    refute has_element?(view, "input[name='sharing[enabled]'][type=checkbox][checked]")
    refute has_element?(view, "input[name='sharing[share_history]'][type=checkbox][checked]")
  end

  test "only the request target can accept or decline and closing a request dialog does not write",
       ctx do
    {view, _} = open(ctx.member, "/family/location_requests/94001")
    render_hook(view, "family_cancel_confirm", %{})
    assert row("SELECT status FROM family_location_requests WHERE id=94001") == [[0]]
    render_hook(view, "family_respond", %{"decision" => "accept", "duration" => "1h"})
    assert row("SELECT status FROM family_location_requests WHERE id=94001") == [[1]]
    assert has_element?(view, "[data-request-status=accepted]")
    render_hook(view, "family_respond", %{"decision" => "decline"})
    assert row("SELECT status FROM family_location_requests WHERE id=94001") == [[1]]
  end

  test "native map event info and params refuse stale actors and clear withdrawn memberships",
       ctx do
    for change <- ["encrypted_password='revoked-session'", "locked_at=now()", "deleted_at=now()"],
        stage <- [:info, :event, :params] do
      original = Accounts.get(ctx.owner.id)
      {view, _} = open(original, "/family")
      Repo.query!("UPDATE users SET #{change} WHERE id=$1", [original.id], log: false)

      case stage do
        :info -> send(view.pid, :family_probe)
        :event -> render_change(view, "family:sharing", %{"sharing" => %{"enabled" => "1"}})
        :params -> render_patch(view, "/family?locale=de")
      end

      assert_redirect(view, "/users/sign_in")

      Repo.query!(
        "UPDATE users SET encrypted_password=$2,locked_at=NULL,deleted_at=NULL WHERE id=$1",
        [original.id, original.encrypted_password],
        log: false
      )
    end

    {view, _} = open(ctx.member, "/family")
    Repo.query!("DELETE FROM family_memberships WHERE user_id=90102", [], log: false)
    send(view.pid, :family_probe)
    refute has_element?(view, "#family-shell")
    assert :sys.get_state(view.pid).socket.assigns.page == nil
    assert_push_event(view, "map:clear", %{code: "not_found"})
  end

  test "invitation capability reveal is scoped HTTP with CSRF and no-store", ctx do
    [[id]] =
      Repo.query!("SELECT id FROM family_invitations WHERE token=$1", ["a9fpl-pending"],
        log: false
      ).rows

    path = "/native/family/invitations/#{id}/copy"
    session = RailsUser.session(ctx.owner.id)
    conn = build_conn() |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    assert get(conn, path).status == 403

    conn =
      conn
      |> Plug.Conn.put_req_header("x-csrf-token", DawarichWeb.RailsCsrf.masked_token(session))

    response = get(conn, path)
    assert response.status == 200
    assert response.resp_body =~ "/invitations/a9fpl-pending"
    assert Plug.Conn.get_resp_header(response, "cache-control") == ["no-store"]
    outsider_session = RailsUser.session(ctx.outsider.id)

    outsider =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(outsider_session))
      |> Plug.Conn.put_req_header(
        "x-csrf-token",
        DawarichWeb.RailsCsrf.masked_token(outsider_session)
      )

    assert get(outsider, path).status in [403, 404]
    Repo.query!("UPDATE family_invitations SET status=3 WHERE id=$1", [id], log: false)
    assert get(conn, path).status == 404
  end
end
