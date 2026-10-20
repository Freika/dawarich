defmodule DawarichWeb.NotificationsNativeEventsTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Notifications, Accounts.Scope}
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    user = RailsUser.insert!(%{id: 11401, email: "native-notices@example.invalid", admin: true})
    scope = Scope.for_user(user, "en")
    %{user: user, scope: scope}
  end

  defp open(user, path),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  defp create(scope, title),
    do: Notifications.create!(Repo, scope.user.id, :info, title, "synthetic safe body")

  defp wake(scope), do: Dawarich.Notifications.Events.broadcast(scope.user.id)

  test "localized notification disable labels preserve cancellation and confirmed deletion", c do
    for {locale, delete, cancel} <- [{"en", "Delete", "Cancel"}, {"de", "Löschen", "Abbrechen"}] do
      id = create(c.scope, "localized confirmation")
      {:ok, view, _} = open(c.user, "/notifications/#{id}?locale=#{locale}")

      button =
        render(view)
        |> LazyHTML.from_document()
        |> LazyHTML.query("#notification-delete-dialog button[phx-disable-with]")

      assert LazyHTML.attribute(button, "phx-disable-with") == [delete]
      assert String.trim(LazyHTML.text(button)) == delete

      backdrop =
        render(view)
        |> LazyHTML.from_document()
        |> LazyHTML.query("#notification-delete-dialog .modal-backdrop")

      assert LazyHTML.attribute(backdrop, "aria-label") == [
               if(locale == "de", do: "Schließen", else: "Close")
             ]

      render_click(view, "choose_notification_delete", %{})
      view |> element("#notification-delete-dialog button", cancel) |> render_click()
      render_click(view, "confirm_notification_delete", %{})
      assert Notifications.get(c.user.id, id)
      render_click(view, "choose_notification_delete", %{})
      view |> element("#notification-delete-dialog .modal-backdrop") |> render_click()
      render_click(view, "confirm_notification_delete", %{})
      assert Notifications.get(c.user.id, id)
      render_click(view, "choose_notification_delete", %{})

      view
      |> element("#notification-delete-dialog button[phx-disable-with]", delete)
      |> render_click()

      assert_redirect(view, "/notifications")
      refute Notifications.get(c.user.id, id)
    end
  end

  test "idle connected native navbars perform no notification queries", c do
    {:ok, view, _} = open(c.user, "/notifications")
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:dawarich, :repo, :query],
        &__MODULE__.query/4,
        {self(), view.pid}
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    send(view.pid, :navbar_refresh)
    render(view)
    assert notification_queries() == 0
  end

  def query(_, _, metadata, {pid, owner}) do
    if self() == owner and String.contains?(metadata.query, "notifications"),
      do: send(pid, :notification_query)
  end

  defp notification_queries(count \\ 0) do
    receive do
      :notification_query -> notification_queries(count + 1)
    after
      0 -> count
    end
  end

  test "create read delete and delete-all update two tabs without refresh", c do
    {:ok, first, _} = open(c.user, "/notifications")
    {:ok, second, _} = open(c.user, "/notifications")
    id = create(c.scope, "two tabs")
    wake(c.scope)
    for view <- [first, second], do: assert(has_element?(view, "#notification_#{id}"))
    {:ok, detail, _} = open(c.user, "/notifications/#{id}")
    wake(c.scope)
    for view <- [first, second], do: assert(has_element?(view, "#notifications-badge.hidden"))
    render_click(detail, "choose_notification_delete", %{})
    render_click(detail, "confirm_notification_delete", %{"id" => "forged"})
    assert_redirect(detail, "/notifications", 1_000)
    wake(c.scope)
    for view <- [first, second], do: refute(has_element?(view, "#notification_#{id}"))
    create(c.scope, "delete all")
    wake(c.scope)
    assert has_element?(first, "#notifications", "delete all")
    render_click(first, "choose_notifications_delete_all", %{})
    render_click(first, "confirm_notifications_delete_all", %{})
    wake(c.scope)
    assert Notifications.page(c.user.id, 1).notifications == []
    refute has_element?(second, "#notifications", "delete all")
  end

  test "notification confirmations cancel ignore forged ids and latch duplicate commands", c do
    id = create(c.scope, "retain until confirmed")
    {:ok, view, html} = open(c.user, "/notifications/#{id}")
    refute html =~ "data-turbo-method"
    refute html =~ "data-turbo-confirm"

    refute html
           |> LazyHTML.from_document()
           |> LazyHTML.query(
             "[data-testid=native-notifications-detail] form[action]:not([phx-submit])"
           )
           |> Enum.any?()

    assert has_element?(view, "form.button_to[phx-submit]")
    render_click(view, "confirm_notification_delete", %{"id" => id})
    assert Notifications.get(c.user.id, id)
    render_click(view, "choose_notification_delete", %{"id" => "foreign"})
    assert has_element?(view, "[role=dialog][open][aria-labelledby=notification-delete-title]")
    render_click(view, "cancel_notification_delete", %{})
    refute has_element?(view, "[role=dialog][open]")
    assert Notifications.get(c.user.id, id)
    {:ok, index, _} = open(c.user, "/notifications")
    render_click(index, "choose_notifications_delete_all", %{})
    render_click(index, "cancel_notifications_delete_all", %{})
    assert Notifications.get(c.user.id, id)
    render_click(index, "choose_notifications_delete_all", %{})
    render_click(index, "confirm_notifications_delete_all", %{"user_id" => "foreign"})
    later = create(c.scope, "after duplicate")
    render_click(index, "confirm_notifications_delete_all", %{})
    assert Notifications.get(c.user.id, later)
  end

  test "native family indicator follows current owner permissions without swallowing family delivery",
       c do
    {:ok, view, _} = open(c.user, "/notifications")
    socket = :sys.get_state(view.pid).socket
    refute socket.assigns.navbar.family.member

    Repo.query!(
      "INSERT INTO families(id,name,creator_id,created_at,updated_at) VALUES(114010,'Synthetic family',11401,now(),now())",
      [],
      log: false
    )

    Repo.query!(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES(114010,11401,0,now(),now())",
      [],
      log: false
    )

    Phoenix.PubSub.broadcast(
      Dawarich.PubSub,
      "family:user:11401",
      {:domain_changed, 11401, :membership}
    )

    render(view)
    assert :sys.get_state(view.pid).socket.assigns.navbar.family.member
    socket = Phoenix.Component.assign(socket, :family_action, :show)

    assert {:cont, fresh} =
             DawarichWeb.NotificationSession.handle_info(
               {:domain_changed, 11401, :membership},
               socket
             )

    assert fresh.assigns.navbar.family.member
    Repo.query!("DELETE FROM family_memberships WHERE user_id=11401", [], log: false)

    Phoenix.PubSub.broadcast(
      Dawarich.PubSub,
      "family:user:11401",
      {:domain_changed, 11401, :membership}
    )

    render(view)
    refute :sys.get_state(view.pid).socket.assigns.navbar.family.member
  end

  test "native identity sessions subscribe before their own page mount", c do
    session = %{
      "rails_user_id" => c.user.id,
      "native_identity" => Dawarich.Accounts.Principal.version(c.user),
      "locale" => "en",
      "self_hosted" => true,
      "request_path" => "/family",
      "query_params" => %{},
      "base_url" => "http://www.example.com"
    }

    socket = %Phoenix.LiveView.Socket{
      endpoint: @endpoint,
      router: DawarichWeb.Router,
      view: DawarichWeb.NotificationsLive.Index,
      transport_pid: self(),
      assigns: %{__changed__: %{}, flash: %{}},
      private: %{
        connect_info: %{session: %{"rails_user_id" => c.user.id}},
        lifecycle: %Phoenix.LiveView.Lifecycle{},
        live_temp: %{}
      }
    }

    assert {:cont, subscribed} = DawarichWeb.LiveAuth.on_mount(:default, %{}, session, socket)
    assert subscribed.assigns[:native]
    wake(c.scope)
    assert_receive {:domain_changed, 11401, :notifications}
  end

  test "native settings params cannot renew a revoked identity", c do
    {:ok, view, _} = open(c.user, "/settings/integrations")

    Repo.query!("UPDATE users SET encrypted_password='native-params-revoked' WHERE id=11401", [],
      log: false
    )

    assert {:error, {:redirect, %{to: "/users/sign_in"}}} =
             render_patch(view, "/settings/integrations?service=teslamate")
  end

  test "global native notification hooks keep their principal credential-free", c do
    Repo.query!("UPDATE users SET api_key='synthetic-native-notice-key' WHERE id=11401", [],
      log: false
    )

    for path <- ["/tags", "/settings/general", "/settings/background_jobs"] do
      {:ok, view, _} = open(c.user, path)
      socket = :sys.get_state(view.pid).socket

      for actor <- [socket.assigns.current_user, socket.assigns.current_scope.user] do
        refute Map.has_key?(actor, :api_key)
        refute Map.has_key?(actor, :encrypted_password)
        assert is_binary(actor.session_version)
      end
    end
  end

  test "revoked native admin admission clears its private notification snapshot", c do
    {:ok, view, _} = open(c.user, "/settings/background_jobs")
    create(c.scope, "private admin notice")
    wake(c.scope)
    assert has_element?(view, "#notifications-list a", "private admin notice")
    socket = :sys.get_state(view.pid).socket

    Repo.query!("UPDATE users SET encrypted_password='native-admin-revoked' WHERE id=11401", [],
      log: false
    )

    assert {:halt, refused} = DawarichWeb.AdminLiveAuth.authorize(socket)
    assert refused.assigns.navbar == nil
    assert refused.assigns.current_user == nil
    assert refused.assigns.current_scope == nil
    assert refused.redirected == {:redirect, %{to: "/users/sign_in", status: 302}}
  end

  test "global native tags and settings navbars receive admitted owner snapshots", c do
    for path <- ["/tags", "/settings/general", "/settings/background_jobs"] do
      {:ok, view, _} = open(c.user, path)
      id = create(c.scope, "global #{path}")
      wake(c.scope)
      assert has_element?(view, "#notifications-list a", "global #{path}")
      assert {:ok, :deleted} = Notifications.delete(c.scope, id)
      wake(c.scope)
      refute has_element?(view, "#notifications-list a", "global #{path}")
    end
  end
end
