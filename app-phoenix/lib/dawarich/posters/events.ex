defmodule Dawarich.Posters.Events do
  @moduledoc false
  def subscribe(user), do: Phoenix.PubSub.subscribe(Dawarich.PubSub, stream(user))
  def unsubscribe(user), do: Phoenix.PubSub.unsubscribe(Dawarich.PubSub, stream(user))
  def stream(user), do: "posters:user:#{user}"

  def broadcast(user, poster),
    do: Phoenix.PubSub.broadcast(Dawarich.PubSub, stream(user), {:poster_changed, user, poster})

  def changed({:poster_changed, user, poster}, user) when is_integer(poster), do: {:ok, poster}
  def changed(_, _), do: :ignore
end
