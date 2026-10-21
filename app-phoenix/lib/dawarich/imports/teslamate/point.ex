defmodule Dawarich.Imports.Teslamate.Point do
  @moduledoc false
  @details_error "TeslaMateApi response did not contain drive details"

  def prepare_drive(result, car, drive, list_units \\ %{}) do
    data = result.drive

    if Map.has_key?(data, "drive_details") and
         (is_nil(data["drive_details"]) or is_list(data["drive_details"])) do
      units = if result.units in [nil, %{}], do: list_units, else: result.units

      Enum.reduce_while(data["drive_details"] || [], {:ok, [], 0}, fn detail,
                                                                      {:ok, rows, skipped} ->
        case prepare(detail, car, drive, units) do
          {:ok, row} -> {:cont, {:ok, [row | rows], skipped}}
          :skip -> {:cont, {:ok, rows, skipped + 1}}
          {:error, _} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, rows, skipped} -> {:ok, Enum.reverse(rows), skipped}
        error -> error
      end
    else
      {:error, @details_error}
    end
  end

  def prepare(detail, car, drive, units) when is_map(detail) do
    with lat when not is_nil(lat) <- coordinate(detail["latitude"], -90, 90),
         lon when not is_nil(lon) <- coordinate(detail["longitude"], -180, 180),
         date when is_binary(date) <- detail["date"],
         {:ok, time, _} <- DateTime.from_iso8601(date),
         {:ok, speed} <- velocity(detail["speed"], units["unit_of_length"]) do
      elevation = number(detail["elevation"])
      battery = detail["usable_battery_level"]

      {:ok,
       %{
         lonlat: "POINT(#{lon} #{lat})",
         timestamp: DateTime.to_unix(time),
         altitude: if(elevation, do: trunc(elevation)),
         altitude_decimal: elevation,
         velocity: speed,
         battery: if(battery in [nil, false], do: detail["battery_level"], else: battery),
         tracker_id: "teslamate-car-#{car}",
         external_track_id: "teslamate-drive-#{drive}",
         raw_data:
           Map.merge(detail, %{
             "teslamate_car_id" => car,
             "teslamate_drive_id" => drive,
             "teslamate_detail_id" => detail["detail_id"]
           })
       }}
    else
      {:error, error} when is_binary(error) -> {:error, error}
      _ -> :skip
    end
  end

  def prepare(_, _, _, _), do: :skip

  defp coordinate(value, min, max) do
    n = number(value)
    if n && n >= min && n <= max, do: n
  end

  defp number(value) when is_number(value), do: value / 1

  defp number(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp number(_), do: nil

  defp velocity(speed, unit) do
    case {number(speed), unit} do
      {nil, _} ->
        {:ok, nil}

      {speed, "km"} ->
        {:ok, speed / 3.6}

      {speed, "mi"} ->
        {:ok, speed * 0.44704}

      {_, unit} ->
        {:error,
         "unsupported length unit: #{if unit in [nil, false, ""], do: "missing", else: unit}"}
    end
  end
end
