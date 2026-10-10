defmodule Dawarich.Imports.Events do
  @moduledoc false
  def subscribe(user_id), do: Phoenix.PubSub.subscribe(Dawarich.PubSub, topic(user_id))

  def broadcast(user_id),
    do: Phoenix.PubSub.broadcast(Dawarich.PubSub, topic(user_id), :imports_changed)

  def enqueue(repo, user_id, event_id, stage) do
    intent =
      Dawarich.Achievements.BulkCheck.child_id(event_id, "imports:#{user_id}:#{stage}")

    receipt = Dawarich.Achievements.BulkCheck.receipt_id(intent, "imports.events.enqueue")

    Dawarich.AfterCommit.once(repo, receipt, fn ->
      Dawarich.AfterCommit.enqueue(repo, Dawarich.Imports.EventsWorker, %{
        "user_id" => user_id,
        "event_id" => intent
      })
    end)
  end

  defp topic(user_id) when is_integer(user_id), do: "imports:user:#{user_id}"
end
