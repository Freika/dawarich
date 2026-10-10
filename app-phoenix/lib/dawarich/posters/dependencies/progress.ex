defmodule Dawarich.Posters.Dependencies.Progress do
  @moduledoc false
  alias Dawarich.Cable.Bus
  alias Dawarich.RailsMessages

  @target ~r/target=\\?"poster_(\d{1,19})\\?"/

  def subscribe(user_id) do
    if Process.whereis(Bus), do: Bus.subscribe(stream(user_id))
    :ok
  end

  def unsubscribe(user_id) do
    if Process.whereis(Bus), do: Bus.unsubscribe(stream(user_id))
    :ok
  end

  def changed(message, user_id) do
    with {:message, channel, payload} <- Bus.event(message),
         true <- channel == stream(user_id),
         [_, id] <- Regex.run(@target, payload) do
      {:ok, String.to_integer(id)}
    else
      _ -> :ignore
    end
  end

  def stream(user_id), do: RailsMessages.broadcasting([{:user, user_id}, "posters"])
end
