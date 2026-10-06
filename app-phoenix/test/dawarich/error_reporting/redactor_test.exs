defmodule Dawarich.ErrorReporting.RedactorTest do
  use Dawarich.ErrorReportingCase, async: false
  require Logger

  test "error envelopes and optional logs redact Rails sensitive fields and synthetic personal data" do
    {error, stack} = exception()

    assert {:ok, _} =
             Sentry.capture_exception(error,
               stacktrace: stack,
               request: %{
                 url: "https://example.invalid/?email=victim@example.invalid",
                 query_string: "otp=654321",
                 data: "private-body",
                 cookies: "private-cookie",
                 headers: %{"Authorization" => "Bearer synthetic-credential"}
               },
               user: %{email: "victim@example.invalid", name: "Synthetic Person"},
               extra: %{
                 args: %{payload: "private-job", nested: %{otp: "654321", latitude: 52.12345}}
               }
             )

    {item, payload} = envelope()
    assert item["type"] == "event"
    assert_private(payload)
    assert hd(payload["exception"])["type"] == "RuntimeError"
    assert hd(payload["exception"])["stacktrace"]["frames"] != []
    Application.put_env(:dawarich, :error_reporting, enable_logs: true)
    Sentry.put_config(:enable_logs, true)
    Dawarich.ErrorReporting.start()

    Logger.error(
      "victim@example.invalid Authorization: Bearer synthetic-credential latitude=52.12345 Synthetic Person",
      otp: "654321"
    )

    Logger.flush()
    Sentry.flush()
    {item, payload} = envelope()
    assert item["type"] == "log"
    assert_private(payload)
    assert payload["items"] != []
    refute_receive {:envelope, _, _}
  end

  test "structured logs are off by default while errors still report" do
    assert Sentry.Config.before_send_log() != nil
    assert {:ok, %{config: config}} = :logger.get_handler_config(:dawarich_sentry)
    refute config.enable_logs
    Logger.error("ordinary message victim@example.invalid")
    Logger.flush()
    Sentry.flush()
    refute_receive {:envelope, _, _}
    {error, stack} = exception()
    assert {:ok, _} = Sentry.capture_exception(error, stacktrace: stack)
    {_item, payload} = envelope()
    assert payload["exception"]
    assert_private(payload)
  end
end
