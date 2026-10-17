defmodule Dawarich.ErrorReporting.Config do
  def from_env(env, _runtime) do
    [
      dsn: present(env["SENTRY_DSN"]),
      environment_name:
        env["SENTRY_CURRENT_ENV"] || env["SENTRY_ENVIRONMENT"] || env["RAILS_ENV"] ||
          env["RACK_ENV"] || "development",
      enable_logs: String.downcase(env["SENTRY_ENABLE_LOGS"] || "false") == "true",
      traces_sample_rate: rate(env["SENTRY_TRACES_SAMPLE_RATE"], 0.05),
      profiles_sample_rate: rate(env["SENTRY_PROFILES_SAMPLE_RATE"], 0.1),
      json_library: Jason,
      client: Dawarich.ErrorReporting.HttpClient
    ]
  end

  def sdk(config) do
    Keyword.drop(config, [:profiles_sample_rate, :traces_sample_rate, :enable_logs]) ++
      [
        before_send: {Dawarich.ErrorReporting.Redactor, :event},
        before_send_log: {Dawarich.ErrorReporting.Redactor, :log},
        enable_logs: false,
        dedup_events: false,
        max_breadcrumbs: 0,
        send_max_attempts: 1,
        send_client_reports: false,
        integrations: [oban: [capture_errors: false], telemetry: [report_handler_failures: false]]
      ]
  end

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value
  defp rate(nil, default), do: default

  defp rate(value, _default) do
    case Float.parse(value) do
      {rate, _} -> rate
      :error -> 0.0
    end
  end
end
