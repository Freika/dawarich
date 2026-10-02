defmodule Dawarich.SafeTimestamp do
  @moduledoc false

  alias Dawarich.Repo

  def range(start_value, end_value, now) do
    [[low, high]] =
      Repo.query!(
        "SELECT extract(epoch FROM make_timestamptz(1970, 1, 1, 0, 0, 0))::bigint, " <>
          "extract(epoch FROM make_timestamptz(2100, 1, 1, 0, 0, 0))::bigint"
      ).rows

    {resolve(start_value, low, high, now), resolve(end_value, low, high, now)}
  end

  defp resolve(nil, _low, _high, _now), do: nil
  defp resolve({:epoch, value}, low, high, _now), do: value |> max(low) |> min(high)

  defp resolve({:text, text}, low, high, now) do
    [[epoch, year]] =
      Repo.query!(
        "SELECT floor(extract(epoch FROM $1::text::timestamptz))::bigint, extract(year FROM $1::text::timestamptz)::int",
        [text]
      ).rows

    if year == 2000 and not String.contains?(text, "2000"),
      do: DateTime.to_unix(now),
      else: epoch |> max(low) |> min(high)
  end
end
