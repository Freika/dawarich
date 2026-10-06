defmodule DawarichWeb.Api.UserZone do
  @moduledoc false

  def name(value) when is_number(value) do
    seconds = if abs(value) <= 13, do: value * 3600, else: value

    Enum.find_value(Dawarich.TimeZoneOptions.list(), fn {label, zone} ->
      case Regex.run(~r/\A\(GMT([+-])(\d{2}):(\d{2})\)/, label) do
        [_, sign, hours, minutes] ->
          offset = (String.to_integer(hours) * 60 + String.to_integer(minutes)) * 60
          offset = if sign == "-", do: -offset, else: offset
          if offset == seconds, do: zone

        _ ->
          nil
      end
    end) || fallback()
  end

  def name(value) when is_binary(value), do: Dawarich.UserTimeZone.name(%{"timezone" => value})
  def name(_value), do: fallback()
  defp fallback, do: Dawarich.UserTimeZone.name(%{})
end
