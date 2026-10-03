defmodule Dawarich.Cable do
  @moduledoc false

  alias Dawarich.Cable.{Bus, Frames}
  alias Dawarich.RailsMessages

  def broadcast_to(channel, streamables, message),
    do: publish([channel | List.wrap(streamables)], Frames.payload(message))

  def turbo(streamables, action, target, html),
    do: publish(streamables, Frames.payload(turbo_tag(action, target, html)))

  def refresh(streamables),
    do: publish(streamables, Frames.payload(~s(<turbo-stream action="refresh"></turbo-stream>)))

  def turbo_tag(action, target, html),
    do:
      ~s(<turbo-stream action="#{escape(action)}" target="#{escape(target)}"><template>) <>
        html <> "</template></turbo-stream>"

  defp publish(parts, payload) do
    case Bus.publish(RailsMessages.broadcasting(parts), payload) do
      {:ok, _receivers} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
