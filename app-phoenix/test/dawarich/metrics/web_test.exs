defmodule Dawarich.Metrics.WebTest do
  use Dawarich.DataCase, async: false
  import Plug.Test
  import Plug.Conn

  setup do
    old = System.get_env("PROMETHEUS_EXPORTER_ENABLED")
    System.put_env("PROMETHEUS_EXPORTER_ENABLED", "true")
    on_exit(fn ->
      if old, do: System.put_env("PROMETHEUS_EXPORTER_ENABLED", old),
        else: System.delete_env("PROMETHEUS_EXPORTER_ENABLED")
    end)
    start_supervised!(Dawarich.Metrics)
    :ok
  end

  test "real native requests and repo queries expose counts durations errors and saturation" do
    header = "Basic " <> Base.encode64((System.get_env("METRICS_USERNAME") || "") <> ":" <> (System.get_env("METRICS_PASSWORD") || ""))
    request = conn(:get, "/metrics?api_key=private-should-not-appear") |> put_req_header("authorization", header)
    assert DawarichWeb.Endpoint.call(request, []).status == 200
    assert DawarichWeb.Endpoint.call(conn(:get, "/metrics"), []).status == 401
    Repo.query!("SELECT 1", [], log: false)
    assert {:error, %Postgrex.Error{}} = Repo.query("SELECT metric_column_does_not_exist", [], log: false)
    Dawarich.Metrics.Web.sample([Repo])
    body = Dawarich.Metrics.scrape()
    assert body =~ ~s(dawarich_web_requests_total{method="GET",route="/metrics",status="200"} 1)
    assert body =~ ~s(dawarich_web_requests_total{method="GET",route="/metrics",status="401"} 1)
    assert body =~ "dawarich_web_request_duration_seconds_count"
    assert body =~ ~s(dawarich_web_errors_total{route="/metrics"} 1)
    assert body =~ "dawarich_db_queries_total"
    assert body =~ "dawarich_db_errors_total"
    assert body =~ "dawarich_db_query_duration_seconds_count"
    assert body =~ "dawarich_db_queue_duration_seconds_count"
    assert body =~ "dawarich_db_pool_busy"
    assert body =~ "dawarich_db_pool_waiting"
    assert body =~ "dawarich_runtime_memory_bytes"
    assert body =~ "dawarich_runtime_processes"
    refute body =~ "private-should-not-appear"
    refute body =~ "metric_column_does_not_exist"
    [_, sum] = Regex.run(~r/dawarich_web_request_duration_seconds_sum\{[^\n]*status="200"[^\n]*\} ([\d.e+-]+)/, body)
    assert {seconds, _} = Float.parse(sum)
    assert seconds > 0 and seconds < 5
    assert body =~ "dawarich_web_active_requests 0"
  end
end
