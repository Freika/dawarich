defmodule Dawarich.Imports.SourceDetector do
  @moduledoc false
  alias Dawarich.Imports.SourceJsonDetector

  @csv_fields ~w(lat latitude y y_pos lon lng long longitude x x_pos timestamp time date datetime when created_at recorded_at fixtime tst altitude alt ele elevation height z speed velocity vel speed_mps speed_kmh accuracy acc horizontal_accuracy hdop precision vertical_accuracy vac vdop battery batt bat battery_level bs heading bearing course cog tracker_id tid device_id device deviceid)

  def detect(path, filename) do
    header = read(path, 2048)
    name = if filename, do: String.downcase(filename)

    cond do
      extension?(name, [".gpx"]) && xml?(read(path, 1024), "gpx") ->
        :gpx

      extension?(name, [".kml", ".kmz"]) && kml?(path, name) ->
        :kml

      extension?(name, [".rec"]) || (name && String.contains?(header, ~s("_type":"location"))) ->
        :owntracks

      extension?(name, [".zip"]) && String.starts_with?(header, <<80, 75, 3, 4>>) ->
        :zip

      extension?(name, [".fit"]) && byte_size(header) >= 12 && binary_part(header, 8, 4) == ".FIT" ->
        :fit

      extension?(name, [".tcx"]) && String.contains?(header, "<TrainingCenterDatabase") ->
        :tcx

      extension?(name, [".csv"]) && csv?(header) ->
        :csv

      true ->
        SourceJsonDetector.detect(strip_bom(read(path, 8192)), read(path, 262_144))
    end
  end

  defp read(path, limit) do
    file = File.open!(path, [:read, :binary])

    try do
      case IO.binread(file, limit) do
        :eof -> ""
        bytes -> bytes
      end
    after
      File.close(file)
    end
  end

  defp extension?(nil, _), do: false
  defp extension?(name, extensions), do: String.ends_with?(name, extensions)

  defp kml?(path, name) do
    bytes = read(path, 1024) |> strip_bom()

    if String.ends_with?(name, ".kmz"),
      do: String.starts_with?(bytes, "PK"),
      else: xml?(bytes, "kml")
  end

  defp xml?(bytes, root) do
    content = bytes |> strip_bom() |> String.trim()
    String.starts_with?(content, ["<?xml", "<#{root}"]) && String.contains?(content, "<#{root}")
  end

  defp strip_bom(<<239, 187, 191, rest::binary>>), do: rest
  defp strip_bom(bytes), do: bytes

  defp csv?(bytes) do
    header = bytes |> String.split("\n", parts: 2) |> hd() |> String.trim()

    header
    |> String.split(~r/[,;\t]/)
    |> Enum.count(fn field ->
      field =
        field
        |> String.trim()
        |> String.replace(["\"", "'"], "")
        |> String.trim()
        |> String.downcase()

      field in @csv_fields
    end) >= 2
  end
end
