defmodule Dawarich.Transportation.SpeedCalibrator do
  @moduledoc false

  alias Dawarich.Transportation.Emissions

  @min_samples 20
  @min_derived_mps 1.0

  @unit_bands [
    {:mps, 1.0, 0.8, 1.25},
    {:knots, 1.0 / 1.944, 1.7, 2.09},
    {:mph, 1.0 / 2.237, 2.09, 2.5},
    {:kmh, 1.0 / 3.6, 3.0, 4.3}
  ]

  def call(rows) do
    case median_ratio(rows) do
      nil ->
        rows

      ratio ->
        case Enum.find(@unit_bands, fn {_unit, _scale, lo, hi} -> ratio >= lo and ratio < hi end) do
          nil -> rows
          {:mps, _scale, _lo, _hi} -> rows
          {_unit, scale, _lo, _hi} -> Enum.map(rows, &rescale(&1, scale))
        end
    end
  end

  defp rescale(%{velocity: v} = row, scale) when is_number(v) and v >= 0 do
    %{row | velocity: v * scale}
  end

  defp rescale(row, _scale), do: row

  defp median_ratio(rows) do
    gap_reset = Emissions.tuning()[:gap_reset_s]

    samples =
      Enum.flat_map(rows, fn row ->
        with velocity when is_number(velocity) and velocity > 0 <- row.velocity,
             dt when is_integer(dt) and dt > 0 and dt <= gap_reset <- row.dt,
             dist_m when not is_nil(dist_m) <- row.dist_m do
          derived = dist_m / dt

          if derived < @min_derived_mps, do: [], else: [velocity / derived]
        else
          _ -> []
        end
      end)

    if length(samples) < @min_samples do
      nil
    else
      sorted = Enum.sort(samples)
      Enum.at(sorted, div(length(sorted), 2))
    end
  end
end
