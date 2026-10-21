defmodule Dawarich.ErrorReporting.Redactor do
  @labels ~w(surface worker queue attempt max_attempts)

  def event(event) do
    %{
      event
      | request: nil,
        user: %{},
        extra: %{},
        contexts: %{},
        breadcrumbs: [],
        message: nil,
        fingerprint: [],
        attachments: [],
        server_name: nil,
        tags: Map.take(event.tags, @labels),
        exception: Enum.map(event.exception, &exception/1),
        threads: scrub_threads(event.threads)
    }
  end

  def log(log) do
    if Application.get_env(:dawarich, :error_reporting, [])[:enable_logs] do
      %{
        log
        | body: "[FILTERED]",
          attributes: %{},
          template: nil,
          parameters: nil,
          trace_id: nil,
          span_id: nil
      }
    end
  end

  defp exception(exception) do
    %{
      exception
      | value: "[FILTERED]",
        stacktrace: stack(exception.stacktrace),
        mechanism: mechanism(exception.mechanism)
    }
  end

  defp mechanism(nil), do: nil
  defp mechanism(mechanism), do: %{mechanism | data: nil, meta: nil}
  defp stack(nil), do: nil
  defp stack(stack), do: %{stack | frames: Enum.map(stack.frames || [], &frame/1)}

  defp frame(frame) do
    %{
      frame
      | vars: nil,
        context_line: nil,
        pre_context: [],
        post_context: [],
        function: frame.function |> to_string() |> String.replace(~r/\(.*\)/s, "([FILTERED])")
    }
  end

  defp scrub_threads(nil), do: nil

  defp scrub_threads(threads),
    do: Enum.map(threads, &Map.update(&1, :stacktrace, nil, fn stack -> stack(stack) end))
end
