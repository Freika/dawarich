defmodule Dawarich.Tracks.CommittedEpoch do
  @moduledoc false
  alias Dawarich.Tracks.NativeChanges

  def defer(repo, payload) do
    key = {__MODULE__, repo}

    case Process.get(key) do
      nil ->
        caller = self()
        handler = {__MODULE__, caller, repo}
        watcher = spawn(fn -> watch(caller, handler) end)
        Process.put(key, {[payload], watcher})

        :ok =
          :telemetry.attach(
            handler,
            repo.config()[:telemetry_prefix] ++ [:query],
            &__MODULE__.outcome/4,
            {caller, key, handler}
          )

      {payloads, watcher} ->
        Process.put(key, {[payload | payloads], watcher})
    end

    :ok
  end

  def outcome(_, _, meta, {caller, key, handler}) do
    if self() == caller do
      case {String.downcase(to_string(meta.query)), meta.result} do
        {"commit", {:ok, _}} -> finish(key, handler, true)
        {"commit", _} -> finish(key, handler, false)
        {"rollback", _} -> finish(key, handler, false)
        _ -> :ok
      end
    end
  end

  defp finish(key, handler, committed?) do
    {payloads, watcher} = Process.delete(key)
    :telemetry.detach(handler)
    send(watcher, :finished)
    if committed?, do: Enum.each(Enum.reverse(payloads), &NativeChanges.bump/1)
    :ok
  end

  defp watch(caller, handler) do
    ref = Process.monitor(caller)

    receive do
      :finished -> Process.demonitor(ref, [:flush])
      {:DOWN, ^ref, :process, ^caller, _} -> :telemetry.detach(handler)
    end
  end
end
