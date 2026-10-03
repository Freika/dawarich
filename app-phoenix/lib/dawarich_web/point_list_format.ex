defmodule DawarichWeb.PointListFormat do
  @moduledoc false

  alias Dawarich.{Geocoding.Normalizer, LocalTime, RubyFloat, RubyInteger}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat, as: SupportFloat

  def coordinates(%{lat: lat, lon: lon}), do: fixed(lat) <> ", " <> fixed(lon)
  defp fixed(value), do: :erlang.float_to_binary(value * 1.0, decimals: 6)

  def velocity(nil, _unit), do: ""

  def velocity(value, unit) when value > 0 do
    kmh = value * 3.6
    speed = if unit == "mi", do: kmh * 0.621371, else: kmh
    speed |> RubyFloat.round(1) |> SupportFloat.to_s()
  end

  def velocity(value, _unit) when is_float(value), do: SupportFloat.to_s(value)
  def velocity(value, _unit), do: to_string(value)

  def speed_class(value),
    do: if(RubyInteger.to_i(value) < 0, do: "text-red-500", else: "text-default")

  def address(point, fallback \\ true) do
    props = Normalizer.from_data(point.geodata).properties
    parts = nonblank([props["street"], props["city"], props["country"]])

    parts =
      if parts == [] and fallback, do: nonblank([point.city, point.country_name]), else: parts

    Enum.join(parts, ", ")
  end

  defp nonblank(parts), do: Enum.reject(parts, &Ruby.blank?/1)

  def url(path, params) do
    query =
      params |> Map.reject(fn {_key, value} -> is_nil(value) end) |> DawarichWeb.Params.to_query()

    if query == "", do: path, else: path <> "?" <> query
  end

  def datetime_param(value, zone) do
    {:ok, _datetime, offset} = DateTime.from_iso8601(value)
    String.replace(binary_part(value, 0, 19), "T", " ") <> " " <> LocalTime.offset(zone, offset)
  end

  def entries(locale, count, page, size, total_pages) do
    entry = if locale == "en" and size != 1, do: "points", else: "point"

    {key, bindings} =
      if total_pages < 2 do
        {"helpers.page_entries_info.one_page.display_entries", %{entry_name: entry, count: count}}
      else
        first = (page - 1) * 50 + 1

        {"helpers.page_entries_info.more_pages.display_entries",
         %{entry_name: entry, first: first, last: first - 1 + size, total: count}}
      end

    bindings = Map.new(bindings, fn {name, value} -> {to_string(name), value} end)
    {:ok, html} = Dawarich.I18n.t(locale, key, bindings)
    Phoenix.HTML.raw(html)
  end
end
