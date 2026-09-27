defmodule Dawarich.Jobs.Housekeeping do
  @moduledoc false

  alias Dawarich.Jobs.Outbox

  @day 86_400

  def run!(repo, now) do
    Outbox.prune!(repo, DateTime.add(now, -7 * @day))

    delete!(
      repo,
      "DELETE FROM phoenix.runtime_nodes WHERE beat_at < $1",
      DateTime.add(now, -@day)
    )

    delete!(
      repo,
      "DELETE FROM phoenix.trip_events WHERE created_at < $1",
      DateTime.add(now, -@day)
    )

    delete!(
      repo,
      "DELETE FROM phoenix.processed_commands WHERE processed_at < $1",
      DateTime.add(now, -30 * @day)
    )

    :ok
  end

  defp delete!(repo, sql, before), do: repo.query!(sql, [before], log: false)
end
