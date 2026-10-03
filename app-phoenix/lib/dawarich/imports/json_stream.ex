defmodule Dawarich.Imports.JsonStream do
  @moduledoc false
  alias Dawarich.Imports.JsonStream.Parser

  defmodule Error do
    defexception message: "Invalid JSON document", reason: :syntax
  end

  @max_heap_bytes 1_073_741_824

  def reduce(path, acc, fun, select \\ fn _ -> false end, opts \\ []) do
    parent = self()
    ref = make_ref()
    limit = Keyword.get(opts, :max_heap_bytes, @max_heap_bytes)
    {pid, monitor} = spawn_monitor(fn -> Parser.run(parent, ref, path, select, opts, limit) end)
    consume(%{pid: pid, monitor: monitor, ref: ref, fun: fun, limit: limit}, acc)
  end

  defp consume(%{ref: ref, monitor: monitor} = run, acc) do
    receive do
      {^ref, :events, events} ->
        acc = apply_events(run, events, acc)
        send(run.pid, {ref, :more})
        consume(run, acc)

      {^ref, :done, events} ->
        acc = apply_events(run, events, acc)
        Process.demonitor(monitor, [:flush])
        acc

      {^ref, :raise, events, kind, reason, stacktrace} ->
        apply_events(run, events, acc)
        Process.demonitor(monitor, [:flush])
        :erlang.raise(kind, reason, stacktrace)

      {:DOWN, ^monitor, :process, _pid, :killed} ->
        raise Error,
          reason: :memory,
          message: "JSON document needs more than #{div(run.limit, 1_048_576)} MiB of memory"

      {:DOWN, ^monitor, :process, _pid, reason} ->
        exit(reason)
    end
  end

  defp apply_events(run, events, acc) do
    Enum.reduce(events, acc, run.fun)
  catch
    kind, reason ->
      Process.demonitor(run.monitor, [:flush])
      Process.exit(run.pid, :kill)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end
end
