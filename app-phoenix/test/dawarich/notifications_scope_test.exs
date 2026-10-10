defmodule Dawarich.NotificationsScopeTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.{Notifications, Accounts.Scope, Accounts.Principal}

  setup do
    user = Dawarich.Test.RailsUser.insert!(%{id: 11201, email: "notice-native@example.invalid"})
    other = Dawarich.Test.RailsUser.insert!(%{id: 11202, email: "notice-other@example.invalid"})
    at = NaiveDateTime.add(NaiveDateTime.utc_now(), -120)

    for {id, owner} <- [{112_010, user.id}, {112_011, user.id}, {112_020, other.id}] do
      Repo.insert_all("notifications", [
        %{
          id: id,
          user_id: owner,
          title: "synthetic #{id}",
          content: "private synthetic text",
          kind: 0,
          created_at: at,
          updated_at: at
        }
      ])
    end

    %{scope: Scope.for_user(Principal.project(user), "en"), at: at}
  end

  test "scoped notification operations refuse foreign stale and deleted actors before effects",
       c do
    assert {:ok, page} = Notifications.page(c.scope, 1)
    assert Enum.sort(Enum.map(page.notifications, & &1.id)) == [112_010, 112_011]
    assert {:error, :not_found} = apply(Notifications, :open, [c.scope, 112_020])
    assert {:error, :not_found} = Notifications.delete(c.scope, 112_020)
    assert {:error, :not_found} = apply(Notifications, :open, [c.scope, "invalid"])
    assert [[nil]] = rows("SELECT read_at FROM notifications WHERE id=112020")

    Repo.query!("UPDATE users SET encrypted_password='native-notice-revoked' WHERE id=11201", [],
      log: false
    )

    assert {:error, :stale_session} = Notifications.page(c.scope, 1)
    assert {:error, :stale_session} = apply(Notifications, :unread, [c.scope])
    assert {:error, :stale_session} = apply(Notifications, :open, [c.scope, 112_010])
    assert {:error, :stale_session} = Notifications.mark_all_read(c.scope)
    assert {:error, :stale_session} = Notifications.delete(c.scope, 112_010)
    assert {:error, :stale_session} = Notifications.delete_all(c.scope)
    assert [[3]] = rows("SELECT count(*) FROM notifications")
    assert [[0]] = rows("SELECT count(*) FROM notifications WHERE read_at IS NOT NULL")
    fresh = Dawarich.Accounts.get(11201) |> Principal.project() |> Scope.for_user("en")
    Repo.query!("UPDATE users SET deleted_at=now() WHERE id=11201", [], log: false)
    assert {:error, :stale_session} = Notifications.delete_all(fresh)
    assert {:error, :stale_session} = Notifications.page(fresh, 1)
    assert [[3]] = rows("SELECT count(*) FROM notifications")
  end

  test "notification opening and mark-all preserve distinct updated_at semantics", c do
    assert {:ok, notice} = apply(Notifications, :open, [c.scope, 112_010])
    assert notice.read_at

    assert [[read, updated]] =
             rows("SELECT read_at,updated_at FROM notifications WHERE id=112010")

    assert read == updated
    assert NaiveDateTime.compare(updated, c.at) == :gt
    assert {:ok, again} = apply(Notifications, :open, [c.scope, 112_010])
    assert again.read_at == read

    assert [[^read, ^updated]] =
             rows("SELECT read_at,updated_at FROM notifications WHERE id=112010")

    assert {:ok, {1, nil}} = Notifications.mark_all_read(c.scope)
    assert [[at]] = rows("SELECT updated_at FROM notifications WHERE id=112011")
    assert at == c.at
    assert [[nil]] = rows("SELECT read_at FROM notifications WHERE id=112020")
    assert {:ok, %{count: 0, items: []}} = apply(Notifications, :unread, [c.scope])
    assert {:ok, :deleted} = Notifications.delete(c.scope, 112_010)
    assert {:error, :not_found} = Notifications.delete(c.scope, 112_010)
    assert {:ok, {1, nil}} = Notifications.delete_all(c.scope)
    assert [[112_020]] = rows("SELECT id FROM notifications")
  end

  test "scoped notification pagination preserves the unread offset quirk", c do
    for n <- 1..20 do
      at = NaiveDateTime.add(c.at, -n * 60)

      Repo.insert_all("notifications", [
        %{
          id: 112_100 + n,
          user_id: 11201,
          title: "older #{n}",
          content: "synthetic",
          kind: 0,
          created_at: at,
          updated_at: at
        }
      ])
    end

    Repo.query!(
      "UPDATE notifications SET read_at=$1 WHERE id=ANY($2)",
      [c.at, [112_010, 112_011, 112_101]],
      log: false
    )

    assert {:ok, first} = Notifications.page(c.scope, 1)
    assert length(first.notifications) == 20
    assert first.total_pages == 2
    assert first.unread_on_page?
    assert {:ok, second} = Notifications.page(c.scope, 2)
    assert Enum.map(second.notifications, & &1.id) == [112_119, 112_120]
    assert Enum.all?(second.notifications, &is_nil(&1.read_at))
    refute second.unread_on_page?
    assert {:ok, %{count: 19, items: items}} = apply(Notifications, :unread, [c.scope])
    assert length(items) == 10
    assert Enum.all?(items, &(&1.id not in [112_010, 112_011, 112_020, 112_101]))
  end
end
