defmodule DawarichWeb.MetricsTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  setup do
    keys = ~w(PROMETHEUS_EXPORTER_ENABLED METRICS_USERNAME METRICS_PASSWORD SELF_HOSTED)
    old = Map.new(keys, &{&1, System.get_env(&1)})
    System.put_env("PROMETHEUS_EXPORTER_ENABLED", "true")
    System.put_env("METRICS_USERNAME", "metrics-test")
    System.put_env("METRICS_PASSWORD", "synthetic-test-password")
    on_exit(fn ->
      Enum.each(old, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)
    start_supervised!(Dawarich.Metrics)
    :ok
  end

  defp request(method, auth \\ nil) do
    conn = conn(method, "/metrics")
    conn = if auth, do: put_req_header(conn, "authorization", auth), else: conn
    DawarichWeb.Endpoint.call(conn, DawarichWeb.Endpoint.init([]))
  end

  defp auth(user, password), do: "Basic " <> Base.encode64(user <> ":" <> password)

  test "metrics requires the existing enable flag and Basic credentials in both deployment modes" do
    for mode <- ["true", "false"] do
      System.put_env("SELF_HOSTED", mode)
      for header <- [nil, "Bearer bad", "Basic ???", auth("bad", "bad")] do
        response = request(:get, header)
        assert response.status == 401
        assert response.resp_body == "Unauthorized"
        assert get_resp_header(response, "www-authenticate") == [~s(Basic realm="Dawarich Metrics")]
      end
      response = request(:get, auth("metrics-test", "synthetic-test-password"))
      assert response.status == 200
      assert response.resp_body =~ "# HELP"
      assert get_resp_header(response, "content-type") == ["text/plain; version=0.0.4"]
      head = request(:head, auth("metrics-test", "synthetic-test-password"))
      assert {head.status, head.resp_body} == {200, ""}
    end

    System.delete_env("METRICS_USERNAME")
    System.delete_env("METRICS_PASSWORD")
    assert request(:get, auth("", "")).status == 200
    System.put_env("METRICS_USERNAME", "")
    System.put_env("METRICS_PASSWORD", "")
    assert request(:get, auth("", "")).status == 200
  end

  test "disabled exporter exposes no metrics" do
    for flag <- ["false", "TRUE", "1", ""] do
      System.put_env("PROMETHEUS_EXPORTER_ENABLED", flag)
      response = request(:get, auth("metrics-test", "synthetic-test-password"))
      assert response.status == 404
      refute response.resp_body =~ "# HELP"
      assert get_resp_header(response, "www-authenticate") == []
    end
    System.delete_env("PROMETHEUS_EXPORTER_ENABLED")
    assert request(:get).status == 404
  end
end
