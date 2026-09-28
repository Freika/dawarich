defmodule Dawarich.NotificationsTest do
  use Dawarich.JobsCase

  alias Dawarich.Notifications

  defp user! do
    [[id]] =
      rows(
        "INSERT INTO users (email, created_at, updated_at) VALUES ('n@example.test', now(), now()) RETURNING id"
      )

    id
  end

  test "create! inserts a Rails notification (integer kind, timestamps) and one event; rollback leaves neither" do
    user_id = user!()
    now = ~N[2026-09-28 10:00:00.123456]

    {:ok, id} =
      ScratchRepo.transaction(fn ->
        Notifications.create!(ScratchRepo, user_id, :warning, "Title", "Body", now)
      end)

    assert rows(
             "SELECT user_id, kind, title, content, created_at, updated_at, read_at FROM notifications WHERE id = $1",
             [id]
           ) == [[user_id, 1, "Title", "Body", now, now, nil]]

    assert rows("SELECT notification_id FROM phoenix.notification_events") == [[id]]

    assert {:error, :rolled_back} =
             ScratchRepo.transaction(fn ->
               Notifications.create!(ScratchRepo, user_id, :error, "Other", "Body")
               ScratchRepo.rollback(:rolled_back)
             end)

    assert rows("SELECT count(*) FROM notifications") == [[1]]
    assert rows("SELECT count(*) FROM phoenix.notification_events") == [[1]]
  end
end
