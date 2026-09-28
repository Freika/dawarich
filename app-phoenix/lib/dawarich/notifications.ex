defmodule Dawarich.Notifications do
  @moduledoc false

  @kinds %{info: 0, warning: 1, error: 2}

  def create!(repo, user_id, kind, title, content, now \\ NaiveDateTime.utc_now()) do
    {:ok, id} =
      repo.transaction(fn ->
        %{rows: [[id]]} =
          repo.query!(
            "INSERT INTO notifications (user_id, kind, title, content, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $5) RETURNING id",
            [user_id, Map.fetch!(@kinds, kind), title, content, now],
            log: false
          )

        repo.query!("INSERT INTO phoenix.notification_events (notification_id) VALUES ($1)", [id],
          log: false
        )

        id
      end)

    id
  end
end
