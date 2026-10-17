defmodule Dawarich.Stats.FailureNotice do
  @moduledoc false

  def create!(repo, user_id, kind, title, content) do
    {:ok, id} =
      Dawarich.Transaction.run(repo, fn ->
        key = Jason.encode!(["failure_notice", user_id, kind, title, content])
        repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", [key], log: false)
        code = %{info: 0, warning: 1, error: 2} |> Map.fetch!(kind)

        case repo.query!(
               "SELECT id FROM notifications WHERE user_id=$1 AND kind=$2 AND title=$3 AND content=$4 AND read_at IS NULL ORDER BY id LIMIT 1",
               [user_id, code, title, content],
               log: false
             ).rows do
          [[id]] -> id
          [] -> Dawarich.Notifications.create!(repo, user_id, kind, title, content)
        end
      end)

    id
  end
end
