defmodule Dawarich.NativeWorker do
  def start(fun) do
    parent = self()

    worker =
      {pid, _} =
      spawn_monitor(fn ->
        result = fun.()
        send(parent, {:native_result, self(), result})
      end)

    ExUnit.Callbacks.on_exit(fn ->
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      receive do: ({:DOWN, ^ref, :process, ^pid, _} -> :ok)
    end)

    worker
  end

  def barrier(parent, stage) do
    send(parent, {:native_stage, self(), stage})
    receive do: (:continue -> :ok)
  end

  def stage({pid, ref}) do
    receive do
      {:native_stage, ^pid, stage} -> {:ok, stage}
      {:DOWN, ^ref, :process, ^pid, reason} -> {:error, reason}
    end
  end

  def complete({pid, ref} = worker) do
    receive do
      {:native_result, ^pid, result} ->
        case exit_reason(worker) do
          :normal -> {:ok, result}
          reason -> {:error, reason}
        end

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:error, reason}
    end
  end

  def exit_reason({pid, ref}) do
    receive do: ({:DOWN, ^ref, :process, ^pid, reason} -> reason)
  end
end
