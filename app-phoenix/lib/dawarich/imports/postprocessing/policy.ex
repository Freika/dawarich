defmodule Dawarich.Imports.Postprocessing.Policy do
  @moduledoc false
  alias Dawarich.Imports.{DateParts, ImportTime, Postprocessing.Snapshot}
  @counts ~w(waypoints_seen trackpoints_seen route_points_seen)

  def extracts?(import) do
    import.source in [0, 3, 4, 13] and import.additional_data_extraction_status == 0 and
      not without_waypoints?(import)
  end

  def tracks?(import, context) do
    not extracts?(import) and
      not (import.additional_data_extraction_status in [1, 2] and not stalled?(import, context))
  end

  defp without_waypoints?(%{source: 4, raw_data: %{} = counts}) do
    Enum.any?(@counts, &Map.has_key?(counts, &1)) and zero?(counts["waypoints_seen"])
  end

  defp without_waypoints?(_), do: false
  defp zero?(nil), do: true
  defp zero?(number) when is_integer(number), do: number == 0

  defp zero?(text) when is_binary(text),
    do: not match?({number, _} when number != 0, Integer.parse(text))

  defp zero?(_), do: true

  defp stalled?(import, context) do
    text = import.additional_data_extraction["started_at"]
    now = Snapshot.clock(context)
    started = if is_binary(text), do: ImportTime.parse(text, context.zone, now)

    if is_nil(started) do
      true
    else
      parts = DateParts.parse(text)
      {sn, sd} = rational(parts["sec_fraction"])
      {on, od} = rational(parts["offset"])
      denominator = sd * od
      remainder = Integer.mod(sn * od - on * sd, denominator)
      {microsecond, _precision} = now.microsecond

      (started - DateTime.to_unix(now) + 21_600) * denominator * 1_000_000 +
        remainder * 1_000_000 <= microsecond * denominator
    end
  rescue
    ArgumentError -> true
  end

  defp rational(nil), do: {0, 1}
  defp rational(number) when is_integer(number), do: {number, 1}
  defp rational(%{"numerator" => number, "denominator" => denominator}), do: {number, denominator}
end
