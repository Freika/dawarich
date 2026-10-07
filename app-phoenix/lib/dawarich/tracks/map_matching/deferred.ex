defmodule Dawarich.Tracks.MapMatching.Deferred do
  alias Dawarich.Tracks.MapMatching.Enqueuer

  def call(repo, id) do
    caller = self()
    handler = {__MODULE__, make_ref()}
    transaction? = repo.in_transaction?()

    {:ok, pid} =
      Task.Supervisor.start_child(Dawarich.Tracks.MapMatching.Tasks, fn ->
        try do
          if committed?(caller, transaction?) do
            result = Enqueuer.call(repo, id)

            :telemetry.execute([:dawarich, :map_matching, :hook], %{}, %{
              track_id: id,
              result: result
            })
          end
        after
          :telemetry.detach(handler)
        end
      end)

    if transaction? do
      :ok =
        :telemetry.attach(
          handler,
          repo.config()[:telemetry_prefix] ++ [:query],
          &__MODULE__.transaction/4,
          {caller, pid}
        )
    end

    send(pid, :registered)
    :deferred
  rescue
    _ -> :error
  end

  def transaction(_, _, meta, {caller, pid}) do
    if self() == caller do
      case {String.downcase(to_string(meta.query)), meta.result} do
        {"commit", {:ok, _}} -> send(pid, :committed)
        {"commit", _} -> send(pid, :rolled_back)
        {"rollback", _} -> send(pid, :rolled_back)
        _ -> :ok
      end
    end
  end

  defp committed?(_, false) do
    receive do: (:registered -> true)
  end

  defp committed?(caller, true) do
    monitor = Process.monitor(caller)

    receive do
      :registered ->
        receive do
          :committed ->
            Process.demonitor(monitor, [:flush])
            true

          :rolled_back ->
            Process.demonitor(monitor, [:flush])
            false

          {:DOWN, ^monitor, :process, ^caller, _} ->
            false
        end

      {:DOWN, ^monitor, :process, ^caller, _} ->
        false
    end
  end
end
