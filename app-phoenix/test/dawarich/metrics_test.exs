defmodule Dawarich.MetricsTest do
  use ExUnit.Case, async: false

  test "enabled web runtime owns one Prometheus reporter while idle role owns none" do
    old = System.get_env("PROMETHEUS_EXPORTER_ENABLED")
    System.put_env("PROMETHEUS_EXPORTER_ENABLED", "true")
    on_exit(fn ->
      if old, do: System.put_env("PROMETHEUS_EXPORTER_ENABLED", old),
        else: System.delete_env("PROMETHEUS_EXPORTER_ENABLED")
    end)

    children = Dawarich.Application.children(:none)
    specs = Enum.map(children, &Supervisor.child_spec(&1, []))
    assert Enum.count(specs, &(&1.id == Dawarich.Metrics)) == 1
    assert Dawarich.Application.children(:sidekiq_idle) == []
    reporter = Enum.find(children, &(Supervisor.child_spec(&1, []).id == Dawarich.Metrics))
    pid = start_supervised!(reporter)
    assert Process.alive?(pid)
    assert Dawarich.Metrics.scrape() =~ "# TYPE dawarich_runtime_memory_bytes gauge"
    assert {:error, {:already_started, ^pid}} = Dawarich.Metrics.start_link([])
  end
end
