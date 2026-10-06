defmodule Dawarich.Metrics.WebTest do
  use Dawarich.DataCase, async: false
  import Plug.Test
  import Plug.Conn

  defmodule PressureRepo do
    use Ecto.Repo, otp_app: :dawarich, adapter: Ecto.Adapters.Postgres
  end

  setup do
    old = System.get_env("PROMETHEUS_EXPORTER_ENABLED")
    System.put_env("PROMETHEUS_EXPORTER_ENABLED", "true")

    on_exit(fn ->
      if old,
        do: System.put_env("PROMETHEUS_EXPORTER_ENABLED", old),
        else: System.delete_env("PROMETHEUS_EXPORTER_ENABLED")
    end)

    start_supervised!(Dawarich.Metrics)
    :ok
  end

  test "real native requests and repo queries expose counts durations errors and saturation" do
    header =
      "Basic " <>
        Base.encode64(
          (System.get_env("METRICS_USERNAME") || "") <>
            ":" <> (System.get_env("METRICS_PASSWORD") || "")
        )

    request =
      conn(:get, "/metrics?api_key=private-should-not-appear")
      |> put_req_header("authorization", header)

    assert DawarichWeb.Endpoint.call(request, []).status == 200
    assert DawarichWeb.Endpoint.call(conn(:get, "/metrics"), []).status == 401
    head = conn(:head, "/metrics") |> put_req_header("authorization", header)
    assert DawarichWeb.Endpoint.call(head, []).status == 200
    hosts = Application.get_env(:dawarich, :allowed_hosts)

    try do
      Application.put_env(:dawarich, :allowed_hosts, :invalid_host_configuration)

      task =
        Task.async(fn ->
          assert_raise Protocol.UndefinedError, fn ->
            request = %{conn(:get, "/metrics") | req_headers: [{"host", "localhost"}]}
            DawarichWeb.Endpoint.call(request, [])
          end
        end)

      Task.await(task)
    after
      Application.put_env(:dawarich, :allowed_hosts, hosts)
    end

    observe_queries!()
    before = Dawarich.Metrics.scrape()
    Repo.query!("SELECT 1", [], log: false)
    assert_receive {:db_query, Repo, successful, {:ok, _}}

    assert {:error, %Postgrex.Error{}} =
             Repo.query("SELECT metric_column_does_not_exist", [], log: false)

    assert_receive {:db_query, Repo, failed, {:error, _}}

    Dawarich.Metrics.Web.sample([Repo])
    body = Dawarich.Metrics.scrape()
    assert body =~ ~s(dawarich_web_requests_total{method="GET",route="/metrics",status="200"} 1)
    assert body =~ ~s(dawarich_web_requests_total{method="GET",route="/metrics",status="401"} 1)
    assert body =~ ~s(dawarich_web_requests_total{method="GET",route="/metrics",status="500"} 1)
    assert body =~ ~s(dawarich_web_requests_total{method="HEAD",route="/metrics",status="200"} 1)
    assert body =~ "dawarich_web_request_duration_seconds_count"
    assert body =~ ~s(dawarich_web_errors_total{route="/metrics"} 2)
    assert metric(body, "queries_total", Repo) - metric(before, "queries_total", Repo) == 2
    assert metric(body, "errors_total", Repo) - metric(before, "errors_total", Repo) == 1

    for {family, measurement} <- [{"query", :query_time}, {"queue", :queue_time}] do
      duration = successful[measurement] + failed[measurement]
      assert duration > 0
      expected = System.convert_time_unit(duration, :native, :nanosecond) / 1_000_000_000
      name = "#{family}_duration_seconds"
      assert metric(body, name <> "_count", Repo) - metric(before, name <> "_count", Repo) == 2
      seconds = metric(body, name <> "_sum", Repo) - metric(before, name <> "_sum", Repo)
      assert seconds > 0 and seconds < 5
      assert_in_delta seconds, expected, 1.0e-9
    end

    assert body =~ "dawarich_runtime_memory_bytes"
    assert body =~ "dawarich_runtime_processes"
    refute body =~ "private-should-not-appear"
    refute body =~ "metric_column_does_not_exist"

    [_, sum] =
      Regex.run(
        ~r/dawarich_web_request_duration_seconds_sum\{[^\n]*status="200"[^\n]*\} ([\d.e+-]+)/,
        body
      )

    assert {seconds, _} = Float.parse(sum)
    assert seconds > 0 and seconds < 5
    assert body =~ "dawarich_web_active_requests 0"
  end

  test "real checked out connections and waiting clients expose pool pressure and queue duration" do
    options =
      Repo.config()
      |> Keyword.merge(
        pool: DBConnection.ConnectionPool,
        pool_size: 1,
        telemetry_prefix: [:dawarich, :repo]
      )

    previous = Application.get_env(:dawarich, PressureRepo)
    Application.put_env(:dawarich, PressureRepo, options)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, PressureRepo, previous),
        else: Application.delete_env(:dawarich, PressureRepo)
    end)

    start_supervised!(PressureRepo)
    observe_queries!()

    client =
      PressureRepo.checkout(fn ->
        queued = Task.async(fn -> PressureRepo.query!("SELECT 1", [], log: false) end)
        await_waiting_client(System.monotonic_time(:millisecond) + 1_000)
        Dawarich.Metrics.Web.sample([PressureRepo])
        body = Dawarich.Metrics.scrape()
        assert metric(body, "pool_size", PressureRepo) == 1
        assert metric(body, "pool_ready", PressureRepo) == 0
        assert metric(body, "pool_busy", PressureRepo) == 1
        assert metric(body, "pool_waiting", PressureRepo) == 1
        queued
      end)

    Task.await(client)
    assert_receive {:db_query, PressureRepo, measurements, {:ok, _}}
    assert measurements.queue_time > 0
    seconds = System.convert_time_unit(measurements.queue_time, :native, :nanosecond) / 1.0e9
    Dawarich.Metrics.Web.sample([PressureRepo])
    body = Dawarich.Metrics.scrape()
    assert_in_delta metric(body, "queue_duration_seconds_sum", PressureRepo), seconds, 1.0e-9
    assert metric(body, "pool_ready", PressureRepo) == 1
    assert metric(body, "pool_busy", PressureRepo) == 0
    assert metric(body, "pool_waiting", PressureRepo) == 0
  end

  def capture_query(_, measurements, metadata, pid),
    do: send(pid, {:db_query, metadata.repo, measurements, metadata.result})

  defp observe_queries! do
    :ok =
      :telemetry.attach(
        __MODULE__,
        [:dawarich, :repo, :query],
        &__MODULE__.capture_query/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(__MODULE__) end)
  end

  defp await_waiting_client(deadline) do
    pools = Ecto.Adapter.lookup_meta(PressureRepo).pid |> DBConnection.get_connection_metrics()

    unless Enum.sum(Enum.map(pools, & &1.checkout_queue_length)) == 1 do
      assert System.monotonic_time(:millisecond) < deadline
      :erlang.yield()
      await_waiting_client(deadline)
    end
  end

  defp metric(body, name, repo) do
    label = Regex.escape(to_string(repo))

    case Regex.run(~r/dawarich_db_#{name}\{repo="#{label}"\} ([\d.e+-]+)/, body) do
      [_, value] ->
        {number, ""} = Float.parse(value)
        number

      nil ->
        0
    end
  end
end
