defmodule Dawarich.Families.Events do
  @moduledoc false

  def subscribe(user_id), do: Phoenix.PubSub.subscribe(Dawarich.PubSub, topic(user_id))

  def broadcast(user_id, kind)
      when kind in [:membership, :consent, :request, :invitation, :lapse, :location] do
    Phoenix.PubSub.broadcast(Dawarich.PubSub, topic(user_id), {:domain_changed, user_id, kind})
  end

  def enqueue(repo, recipients, kind) do
    for user_id <- Enum.uniq(recipients) do
      Dawarich.AfterCommit.enqueue(repo, Dawarich.Families.EventsWorker, %{
        "user_id" => user_id,
        "kind" => Atom.to_string(kind),
        "event_id" => Ecto.UUID.generate()
      })
    end

    :ok
  end

  defp topic(user_id) when is_integer(user_id), do: "family:user:#{user_id}"
end
