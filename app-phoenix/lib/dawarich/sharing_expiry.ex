defmodule Dawarich.SharingExpiry do
  @moduledoc false
  alias Dawarich.Posters.Time
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def public?(%{"enabled" => true} = settings, now, zone) do
    if Ruby.blank?(settings["expiration"]) do
      true
    else
      case parse(settings["expires_at"], now, zone) do
        %NaiveDateTime{} = at -> NaiveDateTime.compare(DateTime.to_naive(now), at) != :gt
        nil -> false
      end
    end
  end

  def public?(_, _, _), do: false

  def parse(text, now, zone) when is_binary(text) do
    Time.parse(text, now, Dawarich.SharingTimeZone.load(zone))
  rescue
    ArgumentError -> nil
  end

  def parse(_, _, _), do: nil
end
