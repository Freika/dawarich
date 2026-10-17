defmodule Dawarich.Cable.Frames do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def welcome, do: encode([{"type", "welcome"}])
  def ping(seconds), do: encode([{"type", "ping"}, {"message", seconds}])

  def confirm(identifier),
    do: encode([{"identifier", identifier}, {"type", "confirm_subscription"}])

  def reject(identifier),
    do: encode([{"identifier", identifier}, {"type", "reject_subscription"}])

  def disconnect(reason, reconnect),
    do: encode([{"type", "disconnect"}, {"reason", reason}, {"reconnect", reconnect}])

  def message(identifier, payload),
    do:
      IO.iodata_to_binary([
        ~s({"identifier":),
        Ruby.json(identifier),
        ~s(,"message":),
        payload,
        ?}
      ])

  def payload(term), do: term |> Ruby.json() |> IO.iodata_to_binary()

  defp encode(pairs), do: payload({:object, pairs})
end
