defmodule Dawarich.Posters.Geometry do
  @moduledoc false
  alias Dawarich.Ingest.Ruby
  alias Dawarich.Posters.Time
  alias DawarichWeb.LocalizedDate
  @tile_pixels 512
  @meters_per_pixel 40_075_016.686 / @tile_pixels

  def distance(settings),
    do: settings |> Map.get("distance", 6000) |> Ruby.to_i() |> clamp(500, 5_000_000)

  def opacity(settings) do
    raw = Ruby.to_f(settings["route_opacity"])
    raw = if raw > 1, do: raw / 100.0, else: raw
    raw = if raw <= 0, do: 1.0, else: raw
    clamp(raw, 0.05, 1.0)
  end

  def width(settings) do
    raw = settings |> Map.get("route_width", 100) |> Ruby.to_f()
    if raw <= 0, do: 1.0, else: clamp(raw / 100.0, 0.5, 3.0)
  end

  def subtitle(settings, locale) do
    Enum.map_join(~w(start_at end_at), " – ", fn key ->
      date = settings[key] |> Time.parse() |> NaiveDateTime.to_date()
      LocalizedDate.l(locale, date, "medium")
    end)
  end

  def intersects?(track, settings, size \\ %{width: 1200, height: 1600}) do
    lat = Ruby.to_f(settings["lat"])
    lon = Ruby.to_f(settings["lon"])
    pixels = world_pixels(lat, distance(settings), size)
    half = :math.pi() * size.height / pixels
    centre = :math.log(:math.tan(:math.pi() / 4 + lat * :math.pi() / 360))
    south = latitude(centre - half)
    north = latitude(centre + half)
    delta = 180.0 * size.width / pixels

    Enum.any?(track["coordinates"], fn segment ->
      Enum.any?(segment, fn [pt_lon, pt_lat] ->
        unless is_number(pt_lat), do: raise(ArgumentError, "poster latitude is not numeric")
        pt_lat >= south and pt_lat <= north and longitude_within?(pt_lon, lon, delta)
      end)
    end)
  end

  defp world_pixels(lat, distance, size) do
    meters = 2 * distance / 3.0 / size.height
    cosine = :math.cos(lat * :math.pi() / 180) |> abs() |> clamp(0.01, 1.0)
    zoom = :math.log2(@meters_per_pixel * cosine / meters)
    @tile_pixels * :math.pow(2, zoom)
  end

  defp latitude(y), do: (2 * :math.atan(:math.exp(y)) - :math.pi() / 2) * 180 / :math.pi()
  defp longitude_within?(_, _, delta) when delta >= 180.0, do: true

  defp longitude_within?(pt_lon, lon, delta) do
    offset = pt_lon - lon + 180.0
    abs(offset - 360.0 * floor(offset / 360.0) - 180.0) <= delta
  end

  defp clamp(value, low, high), do: min(max(value, low), high)
end
