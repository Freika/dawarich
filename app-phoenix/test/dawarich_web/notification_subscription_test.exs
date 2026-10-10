defmodule DawarichWeb.NotificationSubscriptionTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint
  setup do
    user = RailsUser.insert!(%{id: 11301, email: "notice-subscription@example.invalid"})
    at = NaiveDateTime.utc_now()

    Repo.insert_all("notifications", [
      %{
        id: 113_010,
        user_id: user.id,
        title: "private synthetic notice",
        content: "private synthetic body",
        kind: 0,
        created_at: at,
        updated_at: at
      }
    ])

    session = RailsUser.session(user.id)

    conn =
      build_conn()
      |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> RailsUser.connecting_as(user.id)

    %{user: user, conn: conn, session: session}
  end

  test "a queued notification update after signout clears the private snapshot", c do
    {:ok, view, _} = live(c.conn, "/notifications")
    assert has_element?(view, "#notification_113010", "private synthetic notice")
    socket = :sys.get_state(view.pid).socket
    assert :ok = DawarichWeb.NotificationSession.signed_out(c.session)
    assert_redirect(view, "/users/sign_in")

    assert {:halt, cleared} =
             apply(DawarichWeb.NotificationSession, :handle_info, [
               :notification_signed_out,
               socket
             ])

    assert cleared.assigns.notifications == []
    assert cleared.assigns.notification == nil
    assert cleared.assigns.navbar == nil
    assert cleared.assigns.notification_signed_out

    assert {:halt, refused} =
             apply(DawarichWeb.NotificationSession, :handle_info, [
               {:domain_changed, c.user.id, :notifications},
               cleared
             ])

    assert refused.assigns.notifications == []
  end

  test "native notification subscriptions re-admit a revoked actor before reading queued content",
       c do
    {:ok, view, _} = live(c.conn, "/notifications/113010")
    socket = :sys.get_state(view.pid).socket

    Repo.query!(
      "UPDATE users SET encrypted_password='notice-subscription-revoked' WHERE id=11301",
      [],
      log: false
    )

    assert {:halt, cleared} =
             apply(DawarichWeb.NotificationSession, :handle_info, [
               {:domain_changed, c.user.id, :notifications},
               socket
             ])

    assert cleared.assigns.notifications == []
    assert cleared.assigns.notification == nil
    assert cleared.assigns.navbar == nil
    assert cleared.redirected == {:redirect, %{to: "/users/sign_in", status: 302}}
    send(view.pid, {:domain_changed, c.user.id, :notifications})
    assert_redirect(view, "/users/sign_in")
  end

  test "native subscribers ignore foreign owner wakes and recover missed changes from a snapshot",
       c do
    {:ok, view, _} = live(c.conn, "/notifications")
    socket = :sys.get_state(view.pid).socket

    assert {:cont, ^socket} =
             apply(DawarichWeb.NotificationSession, :handle_info, [
               {:domain_changed, 11302, :notifications},
               socket
             ])

    Repo.query!("UPDATE notifications SET title='changed synthetic notice' WHERE id=113010", [],
      log: false
    )

    apply(Dawarich.Notifications.Events, :broadcast, [c.user.id])
    assert has_element?(view, "#notification_113010", "changed synthetic notice")
    {:ok, reopened, _} = live(c.conn, "/notifications")
    assert has_element?(reopened, "#notification_113010", "changed synthetic notice")
  end

  test "native subscriptions clear a deleted detail before delivering its owner wake", c do
    {:ok, view, _} = live(c.conn, "/notifications/113010")
    socket = :sys.get_state(view.pid).socket
    assert has_element?(view, "#detail_notification_113010", "private synthetic body")
    assert {:ok, :deleted} = Dawarich.Notifications.delete(socket.assigns.current_scope, 113_010)

    assert {:halt, cleared} =
             DawarichWeb.NotificationSession.handle_info(
               {:domain_changed, c.user.id, :notifications},
               socket
             )

    assert cleared.assigns.notification == nil
    assert cleared.redirected == {:redirect, %{to: "/notifications", status: 302}}
    Dawarich.Notifications.Events.broadcast(c.user.id)
    assert_redirect(view, "/notifications", 1_000)
  end

  test "native family subscriptions refuse a revoked principal through the scoped contract", c do
    {:ok, view, _} = live(c.conn, "/notifications")
    socket = :sys.get_state(view.pid).socket

    Repo.query!(
      "UPDATE users SET encrypted_password='family-subscription-revoked' WHERE id=$1",
      [c.user.id],
      log: false
    )

    assert {:error, :stale_session} =
             DawarichWeb.NotificationSession.Native.subscribe_family(socket)
  end

  test "family invalidations refresh job navbars while notification delivery remains independent",
       c do
    scope = Dawarich.Accounts.Scope.for_user(c.user, "en")

    assert {:ok, _} =
             Dawarich.Families.create(scope, %{"name" => "Native seams"}, self_hosted: true)

    views =
      for path <- ["/imports", "/exports", "/notifications", "/family"],
          do: elem(live(c.conn, path), 1)

    for view <- views, do: refute(:sys.get_state(view.pid).socket.assigns.navbar.family.sharing)

    assert {:ok, _} =
             Dawarich.Families.set_sharing(scope, %{"enabled" => "1", "duration" => "permanent"},
               self_hosted: true
             )

    Dawarich.Families.Events.broadcast(c.user.id, :consent)

    for view <- views do
      render(view)
      assert :sys.get_state(view.pid).socket.assigns.navbar.family.sharing
    end

    counts =
      Map.new(views, fn view ->
        {view.pid, :sys.get_state(view.pid).socket.assigns.navbar.unread.count}
      end)

    Dawarich.Notifications.create!(Repo, c.user.id, :info, "independent seam notice", "safe body")
    Dawarich.Notifications.Events.broadcast(c.user.id)

    for view <- views do
      render(view)
      assert :sys.get_state(view.pid).socket.assigns.navbar.unread.count == counts[view.pid] + 1
      assert has_element?(view, "#notifications-badge")
    end
  end
end
