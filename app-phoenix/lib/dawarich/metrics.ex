defmodule Dawarich.Metrics do
  @moduledoc false
  use Supervisor
  import Telemetry.Metrics

  def enabled?, do: System.get_env("PROMETHEUS_EXPORTER_ENABLED") == "true"
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  def children({:direct, _, _}), do: []
  def children(_), do: if(enabled?(), do: [__MODULE__], else: [])

  @impl true
  def init(_opts) do
    Supervisor.init(
      [
        {TelemetryMetricsPrometheus.Core,
         name: :dawarich_prometheus, metrics: definitions(), start_async: false},
        Dawarich.Metrics.Web,
        Dawarich.Metrics.Jobs,
        Dawarich.Metrics.Poller
      ],
      strategy: :one_for_all
    )
  end

  def scrape, do: TelemetryMetricsPrometheus.Core.scrape(:dawarich_prometheus)

  def definitions do
    Dawarich.Metrics.Imports.definitions() ++ Dawarich.Metrics.Archive.definitions() ++ Dawarich.Metrics.Jobs.definitions() ++ Dawarich.Metrics.Web.definitions() ++ [
      last_value("dawarich_runtime_memory_bytes",
        event_name: [:dawarich, :runtime],
        measurement: :memory,
        description: "BEAM total memory in bytes"
      ),
      last_value("dawarich_runtime_processes",
        event_name: [:dawarich, :runtime],
        measurement: :processes,
        description: "BEAM process count"
      )
    ]
  end
end
