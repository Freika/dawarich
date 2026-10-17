defmodule Dawarich.Metrics.Jobs do
  @moduledoc false
  use GenServer
  import Telemetry.Metrics

  @states ~w(available scheduled retryable executing completed discarded cancelled suspended)
  @buckets [
    0.005,
    0.01,
    0.025,
    0.05,
    0.1,
    0.25,
    0.5,
    1,
    2.5,
    5,
    10,
    30,
    60,
    120,
    300,
    1800,
    3600,
    21600
  ]
  @queues "SELECT queue, state, count(*)::integer FROM oban.oban_jobs GROUP BY queue, state"
  @latency """
  SELECT queue, greatest(0, extract(epoch FROM now() - min(scheduled_at)
           FILTER (WHERE state IN ('available', 'retryable') AND scheduled_at <= now())))::float,
         max(extract(epoch FROM now() - attempted_at)) FILTER (WHERE state='executing')::float
  FROM oban.oban_jobs WHERE state IN ('available', 'retryable', 'executing') GROUP BY queue
  """

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    events = for event <- [:start, :stop, :exception], do: [:oban, :job, event]
    :ok = :telemetry.attach_many(__MODULE__, events, &__MODULE__.handle_event/4, nil)
    {:ok, opts}
  end

  @impl true
  def terminate(_, _), do: :telemetry.detach(__MODULE__)

  def handle_event([:oban, :job, event], measurements, metadata, _) do
    labels = Map.take(metadata, [:queue, :worker])
    measurements = Map.put(measurements, :count, 1)
    emit(event, measurements, labels)
    if event in [:stop, :exception], do: emit(:finish, measurements, labels)
    if event == :stop and metadata.state == :success, do: emit(:success, %{count: 1}, labels)
  end

  def sample(public_repo \\ Dawarich.Repo, jobs_repo \\ Dawarich.Jobs.repo()) do
    gauges = Dawarich.Admin.JobHealth.load(public_repo, jobs_repo, nil).gauges

    {:ok, :ok} =
      jobs_repo.transaction(fn ->
        jobs_repo.query!("SET LOCAL statement_timeout = '500ms'", [], log: false)
        counts = jobs_repo.query!(@queues, [], log: false).rows
        queues = Enum.uniq(Enum.map(counts, &hd/1) ++ configured_queues())
        totals = Map.new(counts, fn [queue, state, count] -> {{queue, state}, count} end)

        latencies =
          Map.new(jobs_repo.query!(@latency, [], log: false).rows, fn [queue, latency, runtime] ->
            {queue, {latency || 0, runtime || 0}}
          end)

        for queue <- queues do
          for state <- @states,
              do:
                emit(:depth, %{count: totals[{queue, state}] || 0}, %{queue: queue, state: state})

          {latency, runtime} = Map.get(latencies, queue, {0, 0})

          emit(
            :pressure,
            %{latency: latency, runtime: runtime, busy: totals[{queue, "executing"}] || 0},
            %{queue: queue}
          )
        end

        :ok
      end)

    debt(gauges["outbox"], :outbox, :outbox_age, ~w(due scheduled quarantined))
    debt(gauges["rails_commands"], :commands, :commands_age, ~w(due leased retrying dead))
  end

  defp debt(values, event, age_event, states) when is_map(values) do
    for state <- states, do: emit(event, %{count: values[state] || 0}, %{state: state})
    emit(age_event, %{age: values["oldest_due_seconds"] || 0}, %{})
  end

  defp debt(_, _, _, _), do: :ok

  def definitions do
    [
      sum("dawarich_jobs_executed_total",
        event_name: event(:start),
        measurement: :count,
        tags: [:queue, :worker]
      ),
      sum("dawarich_jobs_success_total",
        event_name: event(:success),
        measurement: :count,
        tags: [:queue, :worker]
      ),
      sum("dawarich_jobs_failed_total",
        event_name: event(:exception),
        measurement: :count,
        tags: [:queue, :worker]
      ),
      last_value("dawarich_jobs_depth",
        event_name: event(:depth),
        measurement: :count,
        tags: [:queue, :state]
      ),
      last_value("dawarich_jobs_busy",
        event_name: event(:pressure),
        measurement: :busy,
        tags: [:queue]
      ),
      last_value("dawarich_jobs_queue_latency_seconds",
        event_name: event(:pressure),
        measurement: :latency,
        tags: [:queue]
      ),
      last_value("dawarich_jobs_running_runtime_seconds",
        event_name: event(:pressure),
        measurement: :runtime,
        tags: [:queue]
      ),
      last_value("dawarich_outbox_debt",
        event_name: event(:outbox),
        measurement: :count,
        tags: [:state]
      ),
      last_value("dawarich_outbox_oldest_due_seconds",
        event_name: event(:outbox_age),
        measurement: :age
      ),
      last_value("dawarich_commands_debt",
        event_name: event(:commands),
        measurement: :count,
        tags: [:state]
      ),
      last_value("dawarich_commands_oldest_due_seconds",
        event_name: event(:commands_age),
        measurement: :age
      )
    ] ++
      for {name, measurement} <- [{"runtime", :duration}, {"latency", :queue_time}] do
        distribution("dawarich_jobs_#{name}_seconds",
          event_name: event(:finish),
          measurement: measurement,
          tags: [:queue, :worker],
          unit: {:native, :second},
          reporter_options: [buckets: @buckets]
        )
      end
  end

  defp configured_queues,
    do:
      Application.fetch_env!(:dawarich, Oban)
      |> Keyword.get(:queues, [])
      |> Keyword.keys()
      |> Enum.map(&to_string/1)

  defp event(event), do: [:dawarich, :metrics, :job, event]

  defp emit(event, measurements, labels),
    do: :telemetry.execute(event(event), measurements, labels)
end
