defmodule Dawarich.Imports.Events do
  @moduledoc false
  def subscribe(user_id), do: Phoenix.PubSub.subscribe(Dawarich.PubSub, topic(user_id))

  def broadcast(user_id),
    do: Phoenix.PubSub.broadcast(Dawarich.PubSub, topic(user_id), :imports_changed)

  defp topic(user_id) when is_integer(user_id), do: "imports:user:#{user_id}"
end
