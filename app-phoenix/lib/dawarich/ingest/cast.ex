defmodule Dawarich.Ingest.Cast do
  @moduledoc false

  alias Dawarich.Ingest.{Geo, Ruby}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Support
  alias Dawarich.RubyFloat

  @limit 2_147_483_648
  @plausible 1000
  @enums %{
    battery_status: %{
      "unknown" => 0,
      "unplugged" => 1,
      "charging" => 2,
      "full" => 3,
      "connected_not_charging" => 4,
      "discharging" => 5
    },
    trigger: %{
      "unknown" => 0,
      "background_event" => 1,
      "circular_region_event" => 2,
      "beacon_event" => 3,
      "report_location_message_event" => 4,
      "manual_event" => 5,
      "timer_based_event" => 6,
      "settings_monitoring_event" => 7
    },
    connection: %{"mobile" => 0, "wifi" => 1, "offline" => 2, "unknown" => 4}
  }
  @decimals %{altitude_decimal: {10, 2}, course: {8, 5}, course_accuracy: {8, 5}}
  @integers ~w(accuracy altitude battery vertical_accuracy timestamp)a
  @strings ~w(velocity tracker_id ssid bssid topic ping)a

  def column(:lonlat, wkt), do: Geo.ewkb!(wkt)
  def column(:user_id, id), do: id
  def column(column, value) when column in @integers, do: integer(value)
  def column(column, value) when column in @strings, do: string(value)
  def column(column, value) when column in [:inrids, :in_regions], do: array(value)
  def column(column, value) when column in [:raw_data, :motion_data], do: json(value)

  def column(column, value) when is_map_key(@decimals, column),
    do: decimal(value, @decimals[column])

  def column(column, value) when is_map_key(@enums, column), do: enum(column, value)

  def integer(nil), do: nil
  def integer(value) when is_integer(value), do: plausible(value)
  def integer(value) when is_float(value), do: in_range(trunc(value))

  def integer(value) when is_binary(value),
    do: if(Ruby.blank?(value), do: nil, else: in_range(Ruby.to_i(value)))

  def integer(_value), do: Ruby.unsupported!("boolean or container in an integer column")

  def enum(_column, nil), do: nil
  def enum(_column, value) when is_integer(value), do: plausible(value)
  def enum(_column, value) when is_float(value), do: in_range(trunc(value))

  def enum(column, value) when is_binary(value) do
    case Map.fetch(@enums[column], value) do
      {:ok, number} -> number
      :error -> if Ruby.blank?(value), do: nil, else: numeric_string(value)
    end
  end

  def enum(_column, _value), do: Ruby.unsupported!("boolean or container in an enum column")

  def string(nil), do: nil
  def string(value) when is_integer(value) and abs(value) < @plausible, do: Ruby.to_s(value)

  def string(value) when is_integer(value),
    do: Ruby.unsupported!("integer implausible for this column")

  def string(value) when is_binary(value) or is_float(value), do: Ruby.to_s(value)
  def string(_value), do: Ruby.unsupported!("boolean or container in a string column")

  def array(nil), do: nil
  def array(list) when is_list(list), do: Enum.map(list, &element/1)
  def array(_value), do: Ruby.unsupported!("non-array in a text[] column")

  def json(nil), do: nil
  def json(value), do: value |> Support.json() |> IO.iodata_to_binary()

  def decimal(nil, _ps), do: nil

  def decimal(value, {_p, s}) when is_binary(value),
    do: if(Ruby.blank?(value), do: nil, else: value |> Ruby.to_d() |> Decimal.round(s, :half_up))

  def decimal(value, {p, s}) when is_integer(value) do
    if abs(value) < Integer.pow(10, p - s),
      do: value |> Decimal.new() |> Decimal.round(s, :half_up),
      else: Ruby.unsupported!("integer wider than the decimal column")
  end

  def decimal(value, {p, s}) when is_float(value) do
    value
    |> RubyFloat.round(s)
    |> :erlang.float_to_binary(scientific: min(p, 16) - 1)
    |> Decimal.new()
    |> Decimal.round(s, :half_up)
  end

  def decimal(_value, _ps), do: Ruby.unsupported!("value Rails would coerce into a decimal")

  defp element(nil), do: nil
  defp element(value) when is_binary(value), do: value
  defp element(_value), do: Ruby.unsupported!("non-string array element")

  defp numeric_string(value) do
    number = Ruby.to_i(value)

    if number == 0 and value != "0" and not (value =~ ~r/\A\s*[+-]?\d/),
      do: nil,
      else: in_range(number)
  end

  defp in_range(number) when number >= -@limit and number < @limit, do: number
  defp in_range(_number), do: Ruby.unsupported!("integer out of range")

  defp plausible(number) when abs(number) < @plausible, do: in_range(number)
  defp plausible(_number), do: Ruby.unsupported!("integer implausible for this column")
end
