defmodule Dawarich.Families.Sharing do
  @moduledoc false

  alias Dawarich.Families.Clock

  def enabled?(%{} = settings, now) do
    case settings["family"] do
      nil -> false
      %{} = family -> active?(family["location_sharing"], now)
      _other -> raise ArgumentError, "family settings are not an object"
    end
  end

  def enabled?(_settings, _now), do: raise(ArgumentError, "settings are not an object")

  def config(settings) do
    case settings do
      %{"family" => nil} -> nil
      %{"family" => %{"location_sharing" => nil}} -> nil
      %{"family" => %{"location_sharing" => %{} = config}} -> config
      %{"family" => %{} = family} when not is_map_key(family, "location_sharing") -> nil
      %{} when not is_map_key(settings, "family") -> nil
      _other -> raise ArgumentError, "sharing settings are not an object"
    end
  end

  defp active?(%{"enabled" => true} = sharing, now) do
    case Clock.parse(sharing["expires_at"]) do
      nil -> true
      at -> NaiveDateTime.compare(at, Clock.naive(now)) == :gt
    end
  end

  defp active?(_sharing, _now), do: false
end
