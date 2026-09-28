defmodule Dawarich.NotificationsTest do
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Dawarich.{Notifications, Repo}
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    RailsUser.insert!(%{id: 4301, email: "a5-n@dawarich.test"})
    RailsUser.insert!(%{id: 4302, email: "a5-other@dawarich.test"})
    now = NaiveDateTime.add(NaiveDateTime.utc_now(:second), -60)

    rows =
      for n <- 1..22 do
        %{
          id: 43_000 + n,
          user_id: 4301,
          title: "N #{n}",
          content: "c",
          kind: if(n == 22, do: 2, else: 0),
          read_at: if(n <= 3, do: now),
          created_at: NaiveDateTime.add(now, -n * 60),
          updated_at: now
        }
      end

    other = %{
      id: 43_100,
      user_id: 4302,
      title: "Other",
      content: "c",
      kind: 0,
      read_at: nil,
      created_at: now,
      updated_at: now
    }

    Repo.insert_all("notifications", [other | rows])
    %{now: now}
  end

  defp row(id),
    do:
      Repo.one(
        from(n in "notifications",
          where: n.id == ^id,
          select: %{read_at: n.read_at, updated_at: n.updated_at}
        )
      )

  test "a page holds 20 notifications, newest first" do
    first = Notifications.page(4301, 1)
    assert length(first.notifications) == 20
    assert hd(first.notifications).title == "N 1"
    assert first.total_pages == 2

    second = Notifications.page(4301, 2)
    assert Enum.map(second.notifications, & &1.title) == ["N 21", "N 22"]
    assert List.last(second.notifications).kind == "error"
  end

  test "unread_on_page? is Rails' EXISTS over the unread rows at the page's offset, not the rows shown" do
    assert Notifications.page(4301, 1).unread_on_page?

    second = Notifications.page(4301, 2)
    assert Enum.all?(second.notifications, &is_nil(&1.read_at))
    refute second.unread_on_page?

    from(n in "notifications", where: n.id in [43_001, 43_002])
    |> Repo.update_all(set: [read_at: nil])

    assert Notifications.page(4301, 2).unread_on_page?
  end

  test "only the owner's notification is found, and out-of-range ids find nothing" do
    assert Notifications.get(4301, 43_100) == nil
    assert Notifications.get(4301, 43_001).title == "N 1"
    assert Notifications.get(4301, 9_223_372_036_854_775_808) == nil
  end

  test "opening an unread notification marks it read and bumps updated_at", %{now: now} do
    notification = Notifications.get(4301, 43_010)
    assert Notifications.mark_read(4301, notification).read_at
    assert NaiveDateTime.compare(row(43_010).updated_at, now) == :gt
  end

  test "mark all sets read_at on unread rows only and leaves updated_at", %{now: now} do
    Notifications.mark_all_read(4301)
    assert row(43_010).read_at
    assert NaiveDateTime.compare(row(43_010).updated_at, now) == :eq
    assert NaiveDateTime.compare(row(43_001).read_at, now) == :eq
    refute row(43_100).read_at
  end

  test "deleting removes only the owner's rows" do
    Notifications.delete(4301, 43_100)
    assert row(43_100)
    Notifications.delete_all(4301)
    assert Notifications.page(4301, 1).notifications == []
    assert row(43_100)
  end
end
