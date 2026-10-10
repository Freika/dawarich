defmodule Dawarich.Notifications.Events do
  @moduledoc false
  def subscribe(user_id), do: Phoenix.PubSub.subscribe(Dawarich.PubSub, topic(user_id))

  def broadcast(user_id),
    do:
      Phoenix.PubSub.broadcast(
        Dawarich.PubSub,
        topic(user_id),
        {:domain_changed, user_id, :notifications}
      )

  def enqueue(repo, user_id) do
    Dawarich.AfterCommit.enqueue(repo, Dawarich.Notifications.EventsWorker, %{
      "event_id" => Ecto.UUID.generate(),
      "user_id" => user_id
    })
  end

  defp topic(user_id) when is_integer(user_id), do: "notifications:user:#{user_id}"
end
