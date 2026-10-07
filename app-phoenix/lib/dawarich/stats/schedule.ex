defmodule Dawarich.Stats.Schedule do
  @moduledoc false

  alias Dawarich.Jobs.Ownership
  alias Dawarich.RailsCommands
  alias Dawarich.Stats.{CalculateMonthWorker, EffectIdentity}
  alias Dawarich.Jobs.Processed

  @key "command:stats.calculate_month"

  def calculate(repo, user_id, year, month, notify, opts \\ []) do
    args = %{
      "user_id" => user_id,
      "year" => Dawarich.RubyInteger.to_i(year),
      "month" => Dawarich.RubyInteger.to_i(month),
      "notify_on_failure" => notify
    }

    delay = Keyword.get(opts, :schedule_in, 0)

    event = opts[:event_id] || Ecto.UUID.generate()

    :ok =
      Processed.once(
        repo,
        EffectIdentity.id(event, @key <> ":schedule", args),
        @key <> ":schedule",
        fn ->
          case if(Dawarich.Standalone.enabled?(), do: :oban, else: Ownership.lock(repo, @key)) do
            :oban ->
              native = Map.put(args, "event_id", event)

              options = [unique: [period: :infinity, keys: [:event_id, :user_id, :year, :month]]]

              Oban.insert!(
                Keyword.get(opts, :oban, Oban),
                CalculateMonthWorker.new(native, due_options(opts, delay) ++ options)
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
        end
      )

    :ok
  end

  defp due_options(opts, delay) do
    if clock = opts[:clock],
      do: [scheduled_at: DateTime.from_unix!(clock + delay)],
      else: [schedule_in: delay]
  end
end
