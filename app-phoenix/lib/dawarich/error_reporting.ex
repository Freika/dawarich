defmodule Dawarich.ErrorReporting do
  @scope {__MODULE__, :release_scope}
  @captured {__MODULE__, :release_captured}

  def release(fun) do
    nested = Process.get(@scope, false)
    Process.put(@scope, true)

    try do
      fun.()
    rescue
      error ->
        capture_release(:error, error, __STACKTRACE__)
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        capture_release(kind, reason, __STACKTRACE__)
        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      Process.put(@scope, nested)
      if not nested, do: Process.delete(@captured)
    end
  end

  def capture_release(kind, reason, stack) do
    captured = {kind, reason, stack}

    if Process.get(@captured) != captured do
      Process.put(@captured, captured)
      {:ok, _} = Application.ensure_all_started([:ssl, :inets, :sentry])

      if Sentry.get_dsn() do
        Sentry.capture_exception(Exception.normalize(kind, reason, stack),
          stacktrace: stack,
          result: :sync,
          request_retries: [],
          handled: false,
          tags: %{"surface" => "release"}
        )

        Sentry.flush(timeout: 2_000)
      end
    end

    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  def capture_web(exception, stack) do
    if Sentry.get_dsn(),
      do:
        Sentry.capture_exception(exception,
          stacktrace: stack,
          handled: false,
          tags: %{"surface" => "web"}
        )

    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  def start do
    if Sentry.get_dsn() do
      :telemetry.attach(__MODULE__, [:oban, :job, :exception], &__MODULE__.oban_exception/4, nil)
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

  def oban_exception(
        _event,
        _measurements,
        %{job: job, kind: kind, reason: reason, stacktrace: stack},
        _config
      ) do
    case reason do
      %Oban.PerformError{reason: {action, _}} when action in [:discard, :cancel] ->
        :ok

      _ ->
        error =
          case reason do
            %Oban.PerformError{reason: {:error, error}} when is_exception(error) -> error
            _ -> Exception.normalize(kind, reason, if(is_list(stack), do: stack, else: []))
          end

        Sentry.capture_exception(error,
          stacktrace: if(is_list(stack), do: stack, else: []),
          handled: false,
          tags: %{
            "surface" => "oban",
            "worker" => job.worker,
            "queue" => job.queue,
            "attempt" => job.attempt,
            "max_attempts" => job.max_attempts
          }
        )

        :ok
    end
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
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
