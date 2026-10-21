defmodule Dawarich.Trips.Events do
  @moduledoc false

  def subscribe(trip_id) when is_integer(trip_id),
    do: Phoenix.PubSub.subscribe(Dawarich.PubSub, topic(trip_id))

  def unsubscribe(trip_id) when is_integer(trip_id),
    do: Phoenix.PubSub.unsubscribe(Dawarich.PubSub, topic(trip_id))

  def broadcast(trip_id) when is_integer(trip_id),
    do:
      Phoenix.PubSub.broadcast(Dawarich.PubSub, topic(trip_id), {:domain_changed, trip_id, :trip})

  defp topic(trip_id), do: "trips:trip:#{trip_id}"
end
