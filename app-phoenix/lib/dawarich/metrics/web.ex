defmodule Dawarich.Metrics.Web do
  @moduledoc false
  use GenServer
  import Telemetry.Metrics

  @buckets [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60, 120, 300, 600]
  @events [
    [:phoenix, :endpoint, :start],
    [:phoenix, :endpoint, :stop],
    [:phoenix, :error_rendered],
    [:dawarich, :repo, :query]
  ]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    :ok = :telemetry.attach_many(__MODULE__, @events, &__MODULE__.handle_event/4, nil)
    {:ok, opts}
  end

  @impl true
  def terminate(_, _), do: :telemetry.detach(__MODULE__)

  def handle_event([:phoenix, :endpoint, :start], _, _, _) do
    Process.put({__MODULE__, :request}, System.monotonic_time())
    emit(:active, %{active: 1}, %{})
  end

  def handle_event([:phoenix, :endpoint, :stop], measurements, %{conn: conn}, _) do
    if Process.delete({__MODULE__, :request}), do: finish(measurements, conn, conn.status)
  end

  def handle_event([:phoenix, :error_rendered], _, %{conn: conn, status: status}, _) do
    if started = Process.delete({__MODULE__, :request}) do
      finish(%{duration: System.monotonic_time() - started}, conn, status)
    end
  end

  def handle_event([:dawarich, :repo, :query], measurements, metadata, _) do
    labels = %{repo: metadata.repo}
    emit(:query, Map.put(measurements, :count, 1), labels)
    if match?({:error, _}, metadata.result), do: emit(:db_error, %{count: 1}, labels)
  end

  defp finish(measurements, conn, status) do
    labels = %{route: route(conn), method: method(conn), status: status}
    emit(:request, Map.put(measurements, :count, 1), labels)
    if status >= 400, do: emit(:error, %{count: 1}, labels)
    emit(:active, %{active: -1}, %{})
  end

  def sample(repos \\ [Dawarich.Repo]) do
    Enum.each(repos, fn repo ->
      try do
        meta = Ecto.Adapter.lookup_meta(repo)
        pools = DBConnection.get_connection_metrics(meta.pid)
        ready = Enum.sum(Enum.map(pools, & &1.ready_conn_count))
        waiting = Enum.sum(Enum.map(pools, & &1.checkout_queue_length))
        size = repo.config()[:pool_size] || 10

        emit(:pool, %{size: size, ready: ready, busy: max(size - ready, 0), waiting: waiting}, %{
          repo: repo
        })
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end
    end)
  end

  def definitions do
    [
      sum("dawarich_web_requests_total",
        event_name: event(:request),
        measurement: :count,
        tags: [:method, :route, :status]
      ),
      histogram("dawarich_web_request_duration_seconds", :request, :duration, [
        :method,
        :route,
        :status
      ]),
      sum("dawarich_web_errors_total",
        event_name: event(:error),
        measurement: :count,
        tags: [:route]
      ),
      sum("dawarich_web_active_requests",
        event_name: event(:active),
        measurement: :active,
        reporter_options: [prometheus_type: :gauge]
      ),
      sum("dawarich_db_queries_total",
        event_name: event(:query),
        measurement: :count,
        tags: [:repo]
      ),
      sum("dawarich_db_errors_total",
        event_name: event(:db_error),
        measurement: :count,
        tags: [:repo]
      ),
      histogram("dawarich_db_query_duration_seconds", :query, :query_time, [:repo]),
      histogram("dawarich_db_queue_duration_seconds", :query, :queue_time, [:repo])
    ] ++
      for measurement <- [:size, :ready, :busy, :waiting] do
        last_value("dawarich_db_pool_#{measurement}",
          event_name: event(:pool),
          measurement: measurement,
          tags: [:repo]
        )
      end
  end

  defp histogram(name, event, measurement, tags),
    do:
      distribution(name,
        event_name: event(event),
        measurement: measurement,
        tags: tags,
        unit: {:native, :second},
        reporter_options: [buckets: @buckets]
      )

  defp emit(name, measurements, metadata),
    do: :telemetry.execute(event(name), measurements, metadata)

  defp event(name), do: [:dawarich, :metrics, name]

  defp route(conn) do
    case Phoenix.Router.route_info(DawarichWeb.Router, conn.method, conn.path_info, conn.host) do
      %{route: route} -> route
      _ -> "unmatched"
    end
  end

  defp method(conn) do
    method = conn.private[:dawarich_method] || conn.method
    if method in ~w(GET HEAD POST PUT PATCH DELETE OPTIONS), do: method, else: "OTHER"
  end
end
