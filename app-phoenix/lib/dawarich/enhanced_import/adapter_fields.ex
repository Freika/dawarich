defmodule Dawarich.EnhancedImport.AdapterFields do
  @moduledoc false
  alias Dawarich.Imports.{ActivityType, ImportTime}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def presence(value), do: if(Ruby.present?(value), do: value)
  def plain({:object, pairs}), do: Map.new(pairs, fn {key, value} -> {key, plain(value)} end)
  def plain(value) when is_list(value), do: Enum.map(value, &plain/1)
  def plain(value), do: value
  def float(nil), do: nil
  def float(value) when is_number(value), do: value / 1
  def float(value), do: Ruby.to_f(value)
  def e7(nil), do: nil
  def e7(value), do: float(value) / 10_000_000

  def coordinates(value) do
    if presence(value) do
      parts =
        value |> Ruby.to_s() |> String.replace("°", "") |> String.trim() |> String.split(~r/,\s*/)

      if length(parts) >= 2, do: {float(hd(parts)), float(Enum.at(parts, 1))}
    end
  end

  def humanize(value) do
    if presence(value) do
      value
      |> Ruby.to_s()
      |> String.replace(~r/\ATYPE_/, "")
      |> String.replace(~r/\AINFERRED_/, "")
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)
    end
  end

  def time(value, context) do
    if presence(value) do
      case ImportTime.parse(value, context.zone, context.now) do
        nil -> nil
        stamp -> iso(stamp, context)
      end
    end
  rescue
    ArgumentError -> nil
  end

  def epoch_ms(value, context) do
    if is_binary(value) and value =~ ~r/\A\d+\z/ do
      micros = String.to_integer(value) * 1000
      micros |> DateTime.from_unix!(:microsecond) |> in_zone(context)
    end
  end

  def unix(value, context),
    do: if(presence(value), do: iso(Dawarich.RubyInteger.to_i(value), context))

  defp iso(stamp, context), do: stamp |> DateTime.from_unix!() |> in_zone(context)

  defp in_zone(time, context) do
    name = Dawarich.TimeZoneName.to_iana(context.zone)
    local = Dawarich.Imports.ZonePeriod.load!(name) |> Dawarich.Imports.ZonePeriod.local_now(time)
    offset = NaiveDateTime.diff(local, DateTime.to_naive(time), :second)
    local = %{local | microsecond: {elem(local.microsecond, 0), 6}}
    NaiveDateTime.to_iso8601(local) <> Dawarich.LocalTime.offset(name, offset, :iso)
  end

  def place(id, name, latitude, longitude, semantic_type) do
    %{
      "external_place_id" => id,
      "name" => name,
      "latitude" => latitude,
      "longitude" => longitude,
      "semantic_type" => semantic_type,
      "geodata_extras" => %{},
      "tag_name" => nil,
      "tag_color" => nil
    }
  end

  def visit(place, first, last, confidence, source) do
    %{
      "started_at" => first,
      "ended_at" => last,
      "place" => place,
      "name" => place["name"],
      "confidence" => confidence,
      "source_label" => source
    }
  end

  def track(import, first, last, activity, distance, confidence, source) do
    mode = ActivityType.map(activity)

    if mode && first && last do
      {:ok, time, _} = DateTime.from_iso8601(first)

      %{
        "tracker_id" => "import-#{import.id}-activity-#{DateTime.to_unix(time)}",
        "start_at" => first,
        "end_at" => last,
        "distance_m" => if(distance != nil, do: Dawarich.RubyInteger.to_i(distance)),
        "transportation_mode" => mode,
        "confidence" => confidence,
        "source_label" => source,
        "segments" => [
          %{
            "start_index" => 0,
            "end_index" => 0,
            "transportation_mode" => mode,
            "confidence" => confidence,
            "source_label" => source
          }
        ]
      }
    end
  end

  def emit(nil, acc, _fun), do: acc
  def emit(row, acc, fun), do: fun.(row, acc)
end
