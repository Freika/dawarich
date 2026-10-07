defmodule Dawarich.AfterCommit do
  @moduledoc false

  def enqueue(repo, worker, args, opts \\ []) do
    {:ok, :ok} =
      transaction(repo, fn ->
        if worker in [Dawarich.Points.TileEpochWorker, Dawarich.Points.VisitMonthsWorker],
          do: Dawarich.AfterCommit.Visibility.record(repo, "keys", args)

        repo.insert!(worker.new(args, opts), prefix: "oban", log: false)
        :ok
      end)

    :ok
  end

  def cache(repo, operation, payload) do
    {:ok, :ok} =
      transaction(repo, fn ->
        payload =
          if operation == "tracks",
            do: Dawarich.Tracks.NativeChanges.snapshot(repo, payload),
            else: payload

        Dawarich.AfterCommit.Visibility.record(repo, operation, payload)

        enqueue(repo, Dawarich.AfterCommit.Worker, %{
          "operation" => operation,
          "payload" => payload,
          "intent_id" => Ecto.UUID.generate()
        })
      end)

    :ok
  end

  def with_visibility(repo, operation, payload, effect) do
    {:ok, result} =
      transaction(repo, fn ->
        Dawarich.AfterCommit.Visibility.record(repo, operation, payload)
        effect.()
      end)

    result
  end

  defp transaction(repo, effect) do
    if function_exported?(repo, :in_transaction?, 0) and repo.in_transaction?(),
      do: {:ok, effect.()},
      else: repo.transaction(effect)
  end

  def once(repo, intent, effect),
    do:
      Dawarich.Jobs.Processed.once(repo, intent, "after_commit", fn ->
        Dawarich.Cable.Delivery.with_intent(intent, effect)
      end)
end
