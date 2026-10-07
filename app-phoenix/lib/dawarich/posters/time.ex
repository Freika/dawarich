defmodule Dawarich.Posters.Time do
  @moduledoc false
  alias Dawarich.Imports.{DateParts, ImportTime}

  def parse(text, now \\ DateTime.utc_now(), zone \\ System.get_env("TIME_ZONE", "Europe/Berlin")) do
    parts = DateParts.parse(text)

    case ImportTime.parse(text, zone, now) do
      nil -> nil
      epoch -> epoch |> Kernel.*(1_000_000) |> Kernel.+(fraction(parts)) |> utc()
    end
  end

  def epoch(nil), do: 0

  def epoch(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

  defp fraction(parts) do
    {n, d} = rational(parts["sec_fraction"])
    {offset, scale} = rational(parts["offset"])
    microseconds = Integer.floor_div((n * scale - offset * d) * 1_000_000, d * scale)
    Integer.mod(microseconds, 1_000_000)
  end

  defp rational(nil), do: {0, 1}
  defp rational(%{"numerator" => n, "denominator" => d}), do: {n, d}
  defp rational(integer), do: {integer, 1}

  defp utc(microseconds),
    do: NaiveDateTime.add(~N[1970-01-01 00:00:00], microseconds, :microsecond)
end
