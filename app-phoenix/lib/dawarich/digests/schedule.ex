defmodule Dawarich.Digests.Schedule do
  @moduledoc false

  alias Dawarich.Stats.{DigestsCalculateMonthEffects, DigestsCalculateYearEffects}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.RailsCommands

  def monthly(repo, user_id, year, month, zone, opts \\ []) do
    enqueue(
      repo,
      "month",
      %{
        "user_id" => user_id,
        "year" => Dawarich.RubyInteger.to_i(year),
        "month" => Dawarich.RubyInteger.to_i(month),
        "time_zone" => zone
      },
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
        case if(Dawarich.Standalone.enabled?(),
               do: :oban,
               else: Ownership.lock(repo, "command:" <> type)
             ) do
          :oban ->
            effect =
              if period == "month",
                do: DigestsCalculateMonthEffects,
                else: DigestsCalculateYearEffects

            effect.publish(repo, args, Keyword.put(opts, :scheduled_at, at))

          :sidekiq ->
            due = DateTime.to_unix(at, :microsecond) / 1_000_000
            RailsCommands.insert!(repo, type, Map.put(args, "run_at", due))
        end

        :ok
      end)

    :ok
  end
end
