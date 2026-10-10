defmodule Dawarich.Cable do
  @moduledoc false

  alias Dawarich.Cable.{Bus, Frames}
  alias Dawarich.RailsMessages

  def broadcast_to(channel, streamables, message, opts \\ []),
    do: publish([channel | List.wrap(streamables)], Frames.payload(message), opts)

  def turbo(streamables, action, target, html, opts \\ []),
    do: publish(streamables, Frames.payload(turbo_tag(action, target, html)), opts)

  def refresh(streamables, opts \\ []),
    do:
      publish(
        streamables,
        Frames.payload(~s(<turbo-stream action="refresh"></turbo-stream>)),
        opts
      )

  def turbo_tag(action, target, html),
    do:
      ~s(<turbo-stream action="#{escape(action)}" target="#{escape(target)}"><template>) <>
        html <> "</template></turbo-stream>"

  defp publish(parts, payload, opts) do
    case Bus.publish(RailsMessages.broadcasting(parts), payload, opts) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
