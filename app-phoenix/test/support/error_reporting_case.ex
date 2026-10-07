defmodule Dawarich.ErrorReporting.TestClient do
  @behaviour Sentry.HTTPClient
  def post(_url, headers, body) do
    if pid = Application.get_env(:dawarich, :sentry_test_receiver),
      do: send(pid, {:envelope, headers, body})

    {:ok, 200, [], "{}"}
  end
end

defmodule Dawarich.ErrorReportingCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Dawarich.ErrorReportingCase
    end
  end

  setup do
    saved = [
      dsn: Sentry.get_dsn(),
      client: Sentry.Config.client(),
      send_result: Sentry.Config.send_result(),
      enable_logs: Sentry.Config.enable_logs?()
    ]

    reporting = Application.fetch_env!(:dawarich, :error_reporting)
    Application.put_env(:dawarich, :sentry_test_receiver, self())
    Sentry.put_config(:dsn, "https://public@receiver.example.invalid/1")
    Sentry.put_config(:client, Dawarich.ErrorReporting.TestClient)
    Sentry.put_config(:send_result, :sync)
    Sentry.put_config(:enable_logs, false)
    Dawarich.ErrorReporting.start()

    on_exit(fn ->
      Sentry.flush()
      :logger.remove_handler(:dawarich_sentry)
      :telemetry.detach(Dawarich.ErrorReporting)
      Enum.each(saved, fn {key, value} -> Sentry.put_config(key, value) end)
      Application.put_env(:dawarich, :error_reporting, reporting)
      Application.delete_env(:dawarich, :sentry_test_receiver)
    end)

    :ok
  end

  def envelope do
    assert_receive {:envelope, headers, body}, 1_000
    body = if {"content-encoding", "gzip"} in headers, do: :zlib.gunzip(body), else: body
    [_, item, payload] = String.split(body, "\n", parts: 3)
    {Jason.decode!(item), Jason.decode!(String.trim(payload))}
  end

  def exception do
    try do
      raise "victim@example.invalid Authorization: Bearer synthetic-credential latitude=52.12345 longitude=13.54321"
    rescue
      error -> {error, __STACKTRACE__}
    end
  end

  def assert_private(payload) do
    encoded = Jason.encode!(payload)

    for text <- [
          "victim@",
          "synthetic-credential",
          "52.12345",
          "13.54321",
          "Synthetic Person",
          "654321",
          "private-cookie",
          "private-body",
          "private-job"
        ],
        do: refute(encoded =~ text)
  end
end
