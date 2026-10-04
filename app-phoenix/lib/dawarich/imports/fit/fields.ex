defmodule Dawarich.Imports.Fit.Fields do
  @moduledoc false
  alias Dawarich.Imports.Fit.Definitions

  @types {{1, 255}, {1, 127}, {1, 255}, {2, 32767}, {2, 65535}, {4, 2_147_483_647},
          {4, 4_294_967_295}, {1, 0}, {4, 4_294_967_295}, {8, 18_446_744_073_709_551_615}, {1, 0},
          {2, 0}, {4, 0}, {1, 255}, {8, 9_223_372_036_854_775_807},
          {8, 18_446_744_073_709_551_615}, {8, 0}}
  @record %{
    0 => {"position_lat", :coordinate},
    1 => {"position_long", :coordinate},
    2 => {"altitude", {5, 500}},
    6 => {"speed", {1000, 0}},
    73 => {"enhanced_speed", {1000, 0}},
    253 => {"timestamp", :time}
  }
  @session %{
    2 => {"start_time", :time},
    5 => {"sport", :sport},
    25 => {"first_lap_index", :raw},
    26 => {"num_laps", :raw},
    253 => {"timestamp", :time},
    254 => {"message_index", :raw}
  }
  @lap %{
    2 => {"start_time", :time},
    25 => {"sport", :sport},
    253 => {"timestamp", :time},
    254 => {"message_index", :raw}
  }
  @sports %{
    0 => "generic",
    1 => "running",
    2 => "cycling",
    3 => "transition",
    4 => "fitness_equipment",
    5 => "swimming",
    6 => "basketball",
    7 => "soccer",
    8 => "tennis",
    9 => "american_football",
    10 => "training",
    11 => "walking",
    12 => "cross_country_skiing",
    13 => "alpine_skiing",
    14 => "snowboarding",
    15 => "rowing",
    16 => "mountaineering",
    17 => "hiking",
    18 => "multisport",
    19 => "paddling",
    20 => "flying",
    21 => "e_biking",
    22 => "motorcycling",
    23 => "boating",
    24 => "driving",
    25 => "golf",
    26 => "hang_gliding",
    27 => "horseback_riding",
    28 => "hunting",
    29 => "fishing",
    30 => "inline_skating",
    31 => "rock_climbing",
    32 => "sailing",
    33 => "ice_skating",
    34 => "sky_diving",
    35 => "snowshoeing",
    36 => "snowmobiling",
    37 => "stand_up_paddleboarding",
    38 => "surfing",
    39 => "wakeboarding",
    40 => "water_skiing",
    41 => "kayaking",
    42 => "rafting",
    43 => "windsurfing",
    44 => "kitesurfing",
    45 => "tactical",
    46 => "jumpmaster",
    47 => "boxing",
    48 => "floor_climbing",
    53 => "diving",
    62 => "hiit",
    64 => "racket",
    76 => "water_tubing",
    77 => "wakesurfing",
    254 => "all"
  }

  def read(file, definition) do
    values =
      Map.new(definition.fields, fn {id, size, type} ->
        {id, decode(Definitions.bytes(file, size), type, definition.endian)}
      end)

    Definitions.bytes(file, definition.developer)
    values
  end

  def selected(number, values) do
    profile =
      case number do
        20 -> @record
        18 -> @session
        19 -> @lap
      end

    Map.new(Enum.filter(values, fn {id, _} -> Map.has_key?(profile, id) end), fn {id, value} ->
      {name, conversion} = profile[id]
      {name, convert(value, conversion)}
    end)
  end

  defp decode(bytes, 7, _) do
    case String.split(bytes, <<0>>, parts: 2) |> hd() do
      "" -> nil
      value -> value
    end
  end

  defp decode(bytes, type, endian) do
    type = if type >= tuple_size(@types), do: 0, else: type
    {width, invalid} = elem(@types, type)

    if rem(byte_size(bytes), width) != 0,
      do: raise(ArgumentError, "FIT field size does not match base type")

    values =
      for <<part::binary-size(width) <- bytes>> do
        raw = :binary.decode_unsigned(part, endian)

        cond do
          raw == invalid ->
            nil

          type in [1, 3, 5, 14] and raw >= Integer.pow(2, width * 8 - 1) ->
            raw - Integer.pow(2, width * 8)

          type in [8, 9] ->
            float(part, endian, width)

          true ->
            raw
        end
      end

    if length(values) == 1, do: hd(values), else: values
  end

  defp float(bytes, :little, 4),
    do:
      (
        <<v::little-float-32>> = bytes
        v
      )

  defp float(bytes, :little, 8),
    do:
      (
        <<v::little-float-64>> = bytes
        v
      )

  defp float(bytes, :big, 4),
    do:
      (
        <<v::big-float-32>> = bytes
        v
      )

  defp float(bytes, :big, 8),
    do:
      (
        <<v::big-float-64>> = bytes
        v
      )

  defp convert(nil, _), do: nil

  defp convert(values, conversion) when is_list(values),
    do: Enum.map(values, &convert(&1, conversion))

  defp convert(value, :coordinate), do: value * (180.0 / 2_147_483_648)
  defp convert(value, :time), do: value + 631_065_600
  defp convert(value, :sport), do: @sports[value] || "Undocumented value #{value}"
  defp convert(value, {scale, offset}), do: value / (scale * 1.0) - offset
  defp convert(value, :raw), do: value
end
