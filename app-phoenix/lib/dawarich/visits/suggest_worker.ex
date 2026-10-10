defmodule Dawarich.Visits.SuggestWorker do
  @moduledoc false
  use Oban.Worker, queue: :visit_suggesting, max_attempts: 1

  alias Dawarich.Visits.{Calendar, RealtimeDebouncer, Settings, Suggest}

  @chain [keys: [:event_id, :cursor], period: :infinity, states: :all]
  @keys ~w(user_id start_at end_at stepping time_zone plan_restricted)

  def args_from_command(1, %{} = p) when map_size(p) == 6 do
    with true <- Enum.all?(@keys, &Map.has_key?(p, &1)),
         true <- Enum.all?(["user_id", "start_at", "end_at"], &is_integer(p[&1])),
         true <- p["stepping"] in ["calendar", "fixed"] and is_binary(p["time_zone"]),
         true <- is_boolean(p["plan_restricted"]) do
      {:ok, Map.put(p, "cursor", p["start_at"])}
    else
      _ -> {:error, "invalid_payload"}
    end
  end

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def new(args, opts), do: super(args, Keyword.merge(defaults(args), opts))

  defp defaults(%{"stepping" => "calendar"}), do: [unique: @chain, priority: 0]
  defp defaults(_args), do: [unique: @chain, priority: 1]

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(15)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"cursor" => cursor, "end_at" => stop} = args} = job) do
    repo = Dawarich.Jobs.repo()
    if cursor == args["start_at"], do: RealtimeDebouncer.clear(repo, args["user_id"])

    with %{settings: settings} <- Settings.load(repo, args["user_id"]),
         true <- Settings.policy(settings).suggestions_enabled and cursor < stop do
      next = Calendar.next_day(repo, args["time_zone"], cursor, args["stepping"])
      :ok = Suggest.run(repo, args["user_id"], cursor, min(next, stop), args)
      if next < stop, do: Oban.insert!(job.conf.name, new(Map.put(args, "cursor", next)))
    end

    :ok
  end
end
