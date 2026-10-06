defmodule Dawarich.ErrorReporting do
  def start do
    if Sentry.get_dsn() do
      :logger.remove_handler(:dawarich_sentry)

      :logger.add_handler(:dawarich_sentry, Sentry.LoggerHandler, %{
        filters: [{:surface, {&__MODULE__.logger_surface/2, nil}}],
        config: %{
          capture_excluded_domains: [],
          capture_metadata: [],
          enable_logs: Application.get_env(:dawarich, :error_reporting, [])[:enable_logs] || false
        }
      })
    end

    :ok
  end

  def logger_surface(event, _config) do
    if :bandit in Map.get(event.meta, :domain, []) do
      put_in(event, [:meta, :sentry], tags: %{"surface" => "web"})
    else
      event
    end
  end
end
