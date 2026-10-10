defmodule Dawarich.Families.Events do
  @moduledoc false

  def subscribe(user_id), do: Phoenix.PubSub.subscribe(Dawarich.PubSub, topic(user_id))

  def broadcast(user_id, kind)
      when kind in [:membership, :consent, :request, :invitation, :lapse] do
    Phoenix.PubSub.broadcast(Dawarich.PubSub, topic(user_id), {:domain_changed, user_id, kind})
  end

  defp topic(user_id) when is_integer(user_id), do: "family:user:#{user_id}"
end
