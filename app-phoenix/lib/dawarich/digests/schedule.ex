defmodule Dawarich.Digests.Schedule do
  @moduledoc false

  alias Dawarich.Digests.{MonthlyWorker, YearlyWorker}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.RailsCommands

  def monthly(repo, user_id, year, month, zone, opts \\ []) do
    enqueue(
      repo,
      "month",
      %{"user_id" => user_id, "year" => year, "month" => month, "time_zone" => zone},
      opts
    )
  end

  def yearly(repo, user_id, year, zone, opts \\ []) do
    enqueue(repo, "year", %{"user_id" => user_id, "year" => year, "time_zone" => zone}, opts)
  end

  defp enqueue(repo, period, args, opts) do
    type = "digests.calculate_" <> period
    at = Keyword.get_lazy(opts, :scheduled_at, &DateTime.utc_now/0)

    {:ok, :ok} =
      repo.transaction(fn ->
        case Ownership.lock(repo, "command:" <> type) do
          :oban ->
            worker = if period == "month", do: MonthlyWorker, else: YearlyWorker
            args = Map.put(args, "event_id", Ecto.UUID.generate())
            Oban.insert!(Keyword.get(opts, :oban, Oban), worker.new(args, scheduled_at: at))

          :sidekiq ->
            due = DateTime.to_unix(at, :microsecond) / 1_000_000
            RailsCommands.insert!(repo, type, Map.put(args, "run_at", due))
        end

        :ok
      end)

    :ok
  end
end
