defmodule Dawarich.Stats.Schedule do
  @moduledoc false

  alias Dawarich.Jobs.Ownership
  alias Dawarich.RailsCommands
  alias Dawarich.Stats.CalculateMonthWorker

  @key "command:stats.calculate_month"

  def calculate(repo, user_id, year, month, notify, opts \\ []) do
    args = %{
      "user_id" => user_id,
      "year" => year,
      "month" => month,
      "notify_on_failure" => notify
    }

    delay = Keyword.get(opts, :schedule_in, 0)

    {:ok, :ok} =
      repo.transaction(fn ->
        case Ownership.lock(repo, @key) do
          :oban ->
            Oban.insert!(
              Keyword.get(opts, :oban, Oban),
              CalculateMonthWorker.new(args, schedule_in: delay)
            )

            :ok

          :sidekiq ->
            now = Keyword.get_lazy(opts, :clock, fn -> System.os_time(:second) end)

            RailsCommands.insert!(
              repo,
              "stats.calculate_month",
              Map.put(args, "run_at", now + delay)
            )
        end
      end)

    :ok
  end
end
