defmodule Dawarich.Jobs.Processed do
  @moduledoc false
  def once(repo, event_id, handler, effect) do
    case repo.transaction(fn ->
           if claim!(repo, event_id, handler) do
             case effect.() do
               :ok -> :ok
               unresolved -> repo.rollback(unresolved)
             end
           else
             :ok
           end
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def done?(repo, event_id) do
    %{num_rows: rows} =
      repo.query!(
        "SELECT 1 FROM phoenix.processed_commands WHERE event_id = $1",
        [Ecto.UUID.dump!(event_id)],
        log: false
      )

    rows == 1
  end

  def mark!(repo, event_id, handler) do
    claim!(repo, event_id, handler)
    :ok
  end

  def claim!(repo, event_id, handler) do
    %{num_rows: rows} =
      repo.query!(
        "INSERT INTO phoenix.processed_commands (event_id, handler, processed_at) VALUES ($1, $2, $3) ON CONFLICT (event_id) DO NOTHING RETURNING event_id",
        [Ecto.UUID.dump!(event_id), handler, DateTime.utc_now()],
        log: false
      )

    rows == 1
  end
end
