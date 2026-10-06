defmodule Dawarich.ErrorReporting do
  def start do
    if Sentry.get_dsn() do
      :logger.add_handler(:dawarich_sentry, Sentry.LoggerHandler, %{
        config: %{
          capture_excluded_domains: [],
          capture_metadata: [],
          enable_logs: Application.get_env(:dawarich, :error_reporting, [])[:enable_logs] || false
        }
      })
    end

    :ok
  end
end
