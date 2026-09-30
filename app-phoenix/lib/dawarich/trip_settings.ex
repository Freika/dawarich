defmodule Dawarich.TripSettings do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.{RubyInteger, TimeZoneName}
  alias Dawarich.Trips.Calculation

  @factors %{"km" => 1000, "mi" => 1609.34, "m" => 1, "ft" => 0.3048, "yd" => 0.9144}

  def read(%{} = settings) do
    with {:ok, unit} <- unit(settings["maps"]),
         {:ok, style} <- style(settings["maps_maplibre_style"]),
         {:ok, meters} <- to_i(settings["meters_between_routes"]),
         {:ok, _minutes} <- to_i(settings["minutes_between_routes"]),
         true <- is_nil(settings["timezone"]) or is_binary(settings["timezone"]) do
      {:ok,
       %{
         unit: unit,
         factor: Map.fetch!(@factors, unit),
         style: style,
         meters: if(meters > 0, do: meters, else: 500),
         minutes: Calculation.minutes_between_routes(settings),
         airtrail: Ruby.present?(settings["airtrail_url"]),
         photos: integration?(settings, "immich") or integration?(settings, "photoprism")
       }}
    else
      _ -> :rails
    end
  end

  def read(_settings), do: :rails

  def zone?(%{"timezone" => zone}, resolved) when is_binary(zone),
    do: Ruby.blank?(zone) or TimeZoneName.to_iana(zone) == resolved

  def zone?(_settings, _resolved), do: true

  defp unit(nil), do: {:ok, "km"}
  defp unit(%{} = maps), do: unit_value(maps["distance_unit"])
  defp unit(_maps), do: :rails

  defp unit_value(value) when value in [nil, false], do: {:ok, "km"}
  defp unit_value(value) when is_map_key(@factors, value), do: {:ok, value}
  defp unit_value(_value), do: :rails

  defp style(value) when value in [nil, false], do: {:ok, "light"}
  defp style(value) when is_binary(value), do: {:ok, value}
  defp style(_value), do: :rails

  defp to_i(value) when is_nil(value) or is_integer(value) or is_float(value) or is_binary(value),
    do: {:ok, RubyInteger.to_i(value)}

  defp to_i(_value), do: :rails

  defp integration?(settings, name),
    do: Ruby.present?(settings[name <> "_url"]) and Ruby.present?(settings[name <> "_api_key"])
end
