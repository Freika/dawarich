defmodule Dawarich.EnhancedImport.Deadline do
  @moduledoc false

  def run(fun, %{at: at} = deadline) do
    check!(deadline)

    task =
      Task.async(fn ->
        try do
          {:ok, fun.()}
        catch
          kind, reason -> {:raised, kind, reason, __STACKTRACE__}
        end
      end)

    try do
      case Task.yield(task, max(at - System.monotonic_time(:millisecond), 0)) do
        {:ok, {:ok, value}} -> value
        {:ok, {:raised, kind, reason, stacktrace}} -> :erlang.raise(kind, reason, stacktrace)
        {:exit, reason} -> exit(reason)
        nil -> timeout!(deadline)
      end
    after
      Task.shutdown(task, :brutal_kill)
    end
  end

  def check!(%{at: at} = deadline) do
    if System.monotonic_time(:millisecond) >= at, do: timeout!(deadline)
  end

  defp timeout!(%{minutes: minutes}),
    do: raise("GPX extraction did not finish within #{minutes} minutes")
end
