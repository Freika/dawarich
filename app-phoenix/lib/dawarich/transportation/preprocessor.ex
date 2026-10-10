defmodule Dawarich.Transportation.Preprocessor do
  @moduledoc false

  alias Dawarich.Transportation.{Emissions, SpeedCalibrator}

  def call(rows) do
    rows
    |> SpeedCalibrator.call()
    |> resolve_all()
    |> apply_bearing_deltas()
  end

  defp resolve_all(rows) do
    {resolved, _} = Enum.map_reduce(rows, nil, &resolve_row/2)
    resolved
  end

  defp resolve_row(input_row, previous_valid_speed) do
    row = Map.merge(input_row, %{speed_mps: nil, speed_valid: false, bearing_delta_deg: nil})
    row = resolve_speed(row, previous_valid_speed)
    next_previous = if row.speed_valid, do: row.speed_mps, else: previous_valid_speed
    {row, next_previous}
  end

  defp resolve_speed(row, previous_valid_speed) do
    stored = row.velocity

    if is_number(stored) and stored < 0 do
      row
    else
      speed = stored || derived_speed(row)

      if is_nil(speed) do
        row
      else
        %{
          row
          | speed_mps: speed,
            speed_valid: valid_sample?(row, speed, previous_valid_speed, stored)
        }
      end
    end
  end

  defp derived_speed(row) do
    cond do
      is_nil(row.dt) or row.dt <= 0 or is_nil(row.dist_m) -> nil
      row.dt > Emissions.tuning()[:gap_reset_s] -> nil
      true -> row.dist_m / row.dt
    end
  end

  defp valid_sample?(row, speed, previous_valid_speed, stored) do
    cond do
      not is_nil(row.accuracy) and row.accuracy > Emissions.tuning()[:accuracy_mask_m] -> false
      not is_nil(stored) -> true
      is_nil(row.dt) or row.dt <= 0 -> false
      true -> plausible_acceleration?(speed, previous_valid_speed, row.dt)
    end
  end

  defp plausible_acceleration?(_speed, nil, _dt), do: true

  defp plausible_acceleration?(speed, previous_valid_speed, dt) do
    abs(speed - previous_valid_speed) / dt <= Emissions.tuning()[:accel_mask_mps2]
  end

  defp apply_bearing_deltas(rows) do
    prev_bearings = [nil | Enum.map(rows, & &1.bearing_deg)]

    rows
    |> Enum.zip(prev_bearings)
    |> Enum.map(fn {row, prev_bearing} ->
      if is_nil(prev_bearing) or is_nil(row.bearing_deg) do
        row
      else
        %{row | bearing_delta_deg: circular_delta(prev_bearing, row.bearing_deg)}
      end
    end)
  end

  defp circular_delta(bearing_a, bearing_b) do
    delta = :math.fmod(abs(bearing_b - bearing_a), 360.0)
    if delta > 180.0, do: 360.0 - delta, else: delta
  end
end
