defmodule Dawarich.Imports.Csv.Detector do
  @moduledoc false
  alias Dawarich.Imports.Csv.Records
  alias Dawarich.I18n

  @aliases [
    latitude: ~w(lat latitude y y_pos),
    longitude: ~w(lon lng long longitude x x_pos),
    timestamp: ~w(timestamp time date datetime when created_at recorded_at fixTime tst),
    altitude: ~w(altitude alt ele elevation height z),
    speed: ~w(speed velocity vel speed_mps speed_kmh),
    accuracy: ~w(accuracy acc horizontal_accuracy hdop precision),
    vertical_accuracy: ~w(vertical_accuracy vac vdop),
    battery: ~w(battery batt bat battery_level bs),
    heading: ~w(heading bearing course cog),
    tracker_id: ~w(tracker_id tid device_id device deviceId)
  ]

  defmodule Error do
    defexception message: "CSV detection failed", rails_class: "Csv::Detector::DetectionError"
  end

  def call(path, locale \\ "en") do
    lines =
      path
      |> File.stream!()
      |> Stream.with_index()
      |> Stream.map(fn {line, index} ->
        line = if index == 0, do: strip_bom(line), else: line
        String.replace(line, ~r/(\r\n|\n|\r)\z/, "")
      end)
      |> Stream.reject(&(&1 == ""))
      |> Enum.take(12)

    delimiter = delimiter(lines)

    if lines == [],
      do: raise(Error, message: "Cannot parse nil as CSV", rails_class: "ArgumentError")

    headers = hd(lines) |> Records.parse(delimiter) |> trim()
    columns = columns(headers)

    if Enum.any?([:latitude, :longitude, :timestamp], &is_nil(columns[&1])) do
      {:ok, message} = I18n.t(locale, "services.csv.detector.required_columns_missing")
      raise Error, message: message
    end

    data =
      lines
      |> tl()
      |> Enum.take(10)
      |> Enum.map(&(Records.parse(&1, delimiter) |> trim()))
      |> Enum.filter(&Enum.any?(&1, fn value -> value not in [nil, ""] end))

    %{
      delimiter: delimiter,
      columns: columns,
      coordinate_format: coordinates(data, columns),
      timestamp_format: timestamp(data, columns),
      comma_decimals: comma?(data, columns, delimiter)
    }
  rescue
    e in Records.Error -> raise Error, message: e.message, rails_class: e.rails_class
  end

  defp delimiter(lines) do
    Enum.max_by([",", ";", "\t"], fn delimiter ->
      counts = lines |> Enum.take(5) |> Enum.map(&length(:binary.matches(&1, delimiter)))
      if Enum.any?(counts, &(&1 == 0)) or length(Enum.uniq(counts)) != 1, do: -1, else: hd(counts)
    end)
  end

  defp columns(headers) do
    columns =
      Enum.reduce(@aliases, %{}, fn {key, aliases}, acc ->
        case find(headers, aliases) do
          nil -> acc
          index -> Map.put(acc, key, index)
        end
      end)

    columns =
      Enum.reduce([:latitude, :longitude, :timestamp], columns, fn key, acc ->
        Map.put(acc, key, acc[key] || substring(headers, Atom.to_string(key)))
      end)

    date = find(headers, ["date"])
    time = find(headers, ["time"])

    if date && time do
      combined =
        Enum.map(headers, fn header ->
          if normalized(header) not in ["date", "time"], do: header
        end)

      index =
        find(combined, Keyword.fetch!(@aliases, :timestamp)) || substring(combined, "timestamp")

      if index,
        do: Map.put(columns, :timestamp, index),
        else: Map.merge(columns, %{timestamp_date: date, timestamp_time: time})
    else
      columns
    end
  end

  defp find(headers, aliases) do
    normalized = Enum.map(headers, &normalized/1)

    Enum.find_value(aliases, fn alias ->
      Enum.find_index(normalized, &(&1 == String.downcase(alias)))
    end)
  end

  defp substring(headers, word),
    do: Enum.find_index(headers, &String.contains?(normalized(&1), word))

  defp normalized(nil), do: ""
  defp normalized(value), do: value |> String.downcase() |> String.trim()
  defp trim(nil), do: []
  defp trim(fields), do: Enum.map(fields, fn value -> if value, do: String.trim(value) end)
  defp strip_bom(<<239, 187, 191, rest::binary>>), do: rest
  defp strip_bom(line), do: line
  defp values(data, index), do: data |> Enum.map(&Enum.at(&1, index)) |> Enum.reject(&is_nil/1)

  defp coordinates(data, columns) do
    coords = values(data, columns.latitude) ++ values(data, columns.longitude)

    cond do
      coords == [] ->
        :decimal_degrees

      Enum.any?(coords, &Regex.match?(~r/[NSEW]\z/i, &1)) ->
        :directional

      Enum.all?(coords, fn value ->
        Regex.match?(~r/\A-?\d+\z/, value) && abs(String.to_integer(value)) > 1_000_000
      end) ->
        :e7

      true ->
        :decimal_degrees
    end
  end

  defp timestamp(data, columns) do
    values = values(data, columns.timestamp)

    cond do
      values == [] -> :iso8601
      Enum.all?(values, &Regex.match?(~r/\A\d{10}\z/, &1)) -> :unix_seconds
      Enum.all?(values, &Regex.match?(~r/\A\d{13}\z/, &1)) -> :unix_milliseconds
      true -> :iso8601
    end
  end

  defp comma?(_, _, delimiter) when delimiter != ";", do: false

  defp comma?(data, columns, _) do
    values = values(data, columns.latitude) ++ values(data, columns.longitude)
    Enum.count(values, &String.contains?(&1, ",")) > div(length(values), 2)
  end
end
