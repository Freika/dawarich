defmodule Dawarich.SafeTimestamp do
  @moduledoc false

  alias Dawarich.Repo

  @range "SELECT extract(epoch FROM make_timestamptz(1970, 1, 1, 0, 0, 0))::bigint, " <>
           "extract(epoch FROM make_timestamptz(2100, 1, 1, 0, 0, 0))::bigint, " <>
           "floor(extract(epoch FROM $1::text::timestamptz))::bigint, extract(year FROM $1::text::timestamptz)::int, " <>
           "floor(extract(epoch FROM $2::text::timestamptz))::bigint, extract(year FROM $2::text::timestamptz)::int"

  def range(start_value, end_value, now) do
    [[low, high, start_epoch, start_year, end_epoch, end_year]] =
      Repo.query!(@range, [text(start_value), text(end_value)]).rows

    {resolve(start_value, {start_epoch, start_year}, low, high, now),
     resolve(end_value, {end_epoch, end_year}, low, high, now)}
  end

  defp text({:text, text}), do: text
  defp text(_value), do: nil

  defp resolve(nil, _parsed, _low, _high, _now), do: nil
  defp resolve({:epoch, value}, _parsed, low, high, _now), do: value |> max(low) |> min(high)

  defp resolve({:text, text}, {epoch, year}, low, high, now) do
    if year == 2000 and not String.contains?(text, "2000"),
      do: DateTime.to_unix(now),
      else: epoch |> max(low) |> min(high)
  end
end
