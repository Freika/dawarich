defmodule Dawarich.Imports.Kml.Points do
  @moduledoc false
  alias Dawarich.Imports.JsonStream.Spool
  alias Dawarich.Imports.Kml.TimeRange
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby, as: Number

  def reduce(file, :placemark, import, context, fun) do
    file = bounded_events(file)

    case TimeRange.range(file, context) do
      nil ->
        :ok

      range ->
        speed = velocity(file)

        coords(file, "Point", true)
        |> Enum.take(1)
        |> Enum.each(fn coord ->
          fun.(point(coord, elem(range, 0), speed, import, context))
        end)

        count = coords(file, "LineString", true) |> Enum.count()

        coords(file, "LineString", true)
        |> Stream.with_index()
        |> Enum.each(fn {coord, i} ->
          fun.(point(coord, TimeRange.interpolate(range, count, i), speed, import, context))
        end)

        coords(file, "MultiGeometry", false)
        |> Enum.each(fn coord ->
          fun.(point(coord, elem(range, 0), speed, import, context))
        end)
    end
  end

  def reduce(file, :track, import, context, fun) do
    file = bounded_events(file)
    times = fields(file, fn [{name, _, _} | _] -> name == "when" end)
    coords = fields(file, fn [{name, _, _} | _] -> name == "gx:coord" end)

    Stream.zip(times, coords)
    |> Enum.each(fn {time, text} ->
      attrs =
        try do
          parts = String.split(String.trim(text))

          if length(parts) >= 2 do
            [lon, lat | rest] = Enum.map(parts, &Number.to_f/1)

            point(
              {lon, lat, List.first(rest)},
              TimeRange.parse!(String.trim(time), context),
              0.0,
              import,
              context
            )
          end
        rescue
          ArgumentError -> nil
        end

      if attrs, do: fun.(attrs)
    end)
  end

  def fields(file, predicate) do
    file
    |> events()
    |> Stream.transform(nil, fn
      {:start, [{_, id, _} | _] = nodes}, nil ->
        {[], if(predicate.(nodes), do: {id, ""})}

      {:text, [{_, id, _} | _], chars}, {id, text} ->
        text = text <> chars
        if byte_size(text) > 1_048_576, do: raise(ArgumentError, "KML field token exceeds limit")
        {[], {id, text}}

      {:end, [{_, id, _} | _]}, {id, text} ->
        {[text], nil}

      _, state ->
        {[], state}
    end)
  end

  defp coords(file, geometry, first?) do
    selected =
      if first? do
        file
        |> events()
        |> Enum.find_value(fn
          {:start, [{"coordinates", id, _}, {^geometry, _, _} | _]} -> id
          _ -> nil
        end)
      end

    file
    |> events()
    |> Stream.transform("", fn event, pending ->
      case event do
        {:text, [{"coordinates", id, _} | _] = nodes, text} ->
          if match_coords?(nodes, id, selected, geometry, first?),
            do: split_coords(pending <> text),
            else: {[], pending}

        {:end, [{"coordinates", id, _} | _] = nodes} ->
          if match_coords?(nodes, id, selected, geometry, first?),
            do: {coordinate(pending), ""},
            else: {[], pending}

        _ ->
          {[], pending}
      end
    end)
  end

  defp match_coords?(_, id, selected, _, true), do: id == selected

  defp match_coords?(nodes, _, _, geometry, false),
    do: Enum.any?(tl(nodes), fn {name, _, _} -> name == geometry end)

  defp split_coords(text) do
    parts = String.split(text, ~r/\s+/, trim: false)

    if byte_size(List.last(parts)) > 1_048_576,
      do: raise(ArgumentError, "KML coordinate token exceeds limit")

    {Enum.flat_map(Enum.drop(parts, -1), &coordinate/1), List.last(parts)}
  end

  defp coordinate(text) do
    case String.split(text, ",", trim: false) do
      [lon, lat | rest] ->
        [{Number.to_f(lon), Number.to_f(lat), Number.to_f(List.first(rest) || "")}]

      _ ->
        []
    end
  end

  defp velocity(file) do
    Enum.find_value(~w(speed Speed velocity), fn key ->
      values =
        fields(file, fn
          [{"value", _, _}, {"Data", _, %{"name" => ^key}} | _] -> true
          _ -> false
        end)
        |> Enum.take(1)

      if values != [], do: {:found, List.first(values)}
    end)
    |> case do
      {:found, text} -> Float.round(Number.to_f(text), 1)
      nil -> 0.0
    end
  end

  defp bounded_events(path) when is_binary(path) do
    if File.stat!(path).size <= 65_536, do: Enum.to_list(events(path)), else: path
  end

  defp bounded_events(events), do: events

  defp events(path) when is_binary(path), do: Spool.stream(path, [:raw, read_ahead: 65_536])
  defp events(events), do: events

  defp point({lon, lat, alt}, time, speed, import, context) do
    now =
      case context.now do
        fun when is_function(fun, 0) -> fun.()
        now -> now
      end

    now = if match?(%DateTime{}, now), do: DateTime.to_naive(now), else: now

    attrs = %{
      lonlat: "POINT(#{Number.to_s(lon)} #{Number.to_s(lat)})",
      timestamp: time,
      altitude: alt,
      velocity: speed,
      user_id: import.user_id,
      import_id: import.id,
      created_at: now,
      updated_at: now
    }

    if context.altitude_decimal?, do: Map.put(attrs, :altitude_decimal, alt), else: attrs
  end
end
