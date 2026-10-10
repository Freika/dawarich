defmodule Dawarich.Sharing.PublicEvents do
  @moduledoc false
  def enqueue(repo, user) do
    ids =
      repo.query!(
        "SELECT id::text FROM shared_links WHERE user_id=$1 AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at>NOW())",
        [user],
        log: false
      ).rows
      |> List.flatten()

    if ids != [], do: Dawarich.Sharing.Events.enqueue(repo, user, ids)
    :ok
  end
end
