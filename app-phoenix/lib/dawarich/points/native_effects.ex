defmodule Dawarich.Points.NativeEffects do
  @moduledoc false

  def native?(repo, key),
    do:
      Dawarich.Standalone.enabled?() or
        repo.query!("SELECT owner FROM phoenix.job_owners WHERE key=$1 FOR SHARE", [key],
          log: false
        ).rows == [["oban"]]

  def enqueue(repo, worker, args, opts \\ []) do
    repo.insert!(worker.new(args, opts), prefix: "oban", log: false)
    :ok
  end

  def achievements(repo, payload) do
    {:ok, :ok} =
      repo.transaction(fn ->
        if native?(repo, "command:achievements.check"),
          do: enqueue(repo, Dawarich.Achievements.CheckWorker, Map.put(payload, "notify", true)),
          else: Dawarich.RailsCommands.insert!(repo, "achievements.check", payload)
      end)

    :ok
  end
end
