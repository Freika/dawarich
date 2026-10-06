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
    cond do
      :bandit in Map.get(event.meta, :domain, []) ->
        put_in(event, [:meta, :sentry], tags: %{"surface" => "web"})

      live_crash?(event.meta[:crash_reason]) ->
        put_in(event, [:meta, :sentry], tags: %{"surface" => "live_view"})

      true ->
        event
    end
  end

  defp live_crash?({_reason, stack}) when is_list(stack) do
    Enum.any?(stack, fn {module, _, _, _} ->
      String.starts_with?(to_string(module), "Elixir.Phoenix.LiveView.")
    end)
  end

  defp live_crash?(_), do: false
end
