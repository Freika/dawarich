defmodule Dawarich.Exports.Events do
  @moduledoc false
  def subscribe(user_id), do: Phoenix.PubSub.subscribe(Dawarich.PubSub, topic(user_id))

  def broadcast(user_id),
    do:
      Phoenix.PubSub.broadcast(
        Dawarich.PubSub,
        topic(user_id),
        {:domain_changed, user_id, :exports}
      )

  def enqueue(repo, user_id, event_id, stage) do
    intent = Dawarich.AfterCommit.identity(event_id, "exports:#{user_id}:#{stage}")
    receipt = Dawarich.AfterCommit.identity(intent, "exports.events.enqueue")

    Dawarich.AfterCommit.once(repo, receipt, fn ->
      Dawarich.AfterCommit.enqueue(repo, Dawarich.Exports.EventsWorker, %{
        "user_id" => user_id,
        "event_id" => intent
      })
    end)
  end

  def native?(repo, type) do
    key = if type == 0, do: "command:exports.points", else: "command:users.export_data"
    Dawarich.Standalone.enabled?() or Dawarich.Jobs.Ownership.lock(repo, key) == :oban
  end

  def restored(repo, user_id, id, type, stage) do
    if native?(repo, type),
      do: enqueue(repo, user_id, Dawarich.AfterCommit.identity(id, "exports.restore"), stage)
  end

  defp topic(user_id) when is_integer(user_id), do: "exports:user:#{user_id}"
end
