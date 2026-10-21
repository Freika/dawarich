defmodule Dawarich.Stats.FullRecalculation do
  @moduledoc false

  alias Dawarich.Jobs.Processed
  alias Dawarich.Stats.{Schedule, TrackedMonths}
  alias Dawarich.State

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  def run(repo, %{"user_id" => user_id, "event_id" => event_id}, opts \\ []) do
    repo.transaction(fn ->
      if Processed.claim!(repo, event_id, "stats.full_recalculation") do
        State.unclaim(repo, "stats_full_recalculation:user:#{user_id}")

        if repo.query!("SELECT id FROM users WHERE id=$1 AND deleted_at IS NULL", [user_id],
             log: false
           ).num_rows == 1 do
          for %{year: year, months: months} <- TrackedMonths.call(repo, user_id),
              month <- months do
            number = Enum.find_index(@months, &(&1 == month)) + 1

            Schedule.calculate(
              repo,
              user_id,
              year,
              number,
              true,
              Keyword.put(opts, :event_id, event_id)
            )

            Keyword.get(opts, :after_child, fn _, _ -> :ok end).(year, number)
          end
        end
      end

      :ok
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
