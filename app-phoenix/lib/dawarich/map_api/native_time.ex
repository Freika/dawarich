defmodule Dawarich.MapApi.NativeTime do
  @moduledoc false
  alias Dawarich.Imports.ImportTime

  def parse(value, zone, now) when is_binary(value) do
    case ImportTime.parse(value, zone, now) do
      nil ->
        nil

      epoch ->
        case Dawarich.Imports.DateParts.parse(value)["sec_fraction"] do
          %{"numerator" => n, "denominator" => d} -> epoch + n / d
          _ -> epoch
        end
    end
  rescue
    _ -> nil
  end

  def parse(_, _zone, _now), do: nil

  def safe(value, zone, now) do
    epoch =
      if is_binary(value) and value =~ ~r/\A\d+\z/,
        do: String.to_integer(value),
        else: parse(value, zone, now) || DateTime.to_unix(now)

    epoch
    |> trunc()
    |> max(-62_135_596_800)
    |> min(253_402_300_799)
    |> DateTime.from_unix!()
    |> DateTime.to_iso8601()
  end

  def iso(epoch),
    do:
      epoch
      |> Kernel.*(1_000_000)
      |> round()
      |> DateTime.from_unix!(:microsecond)
      |> DateTime.to_iso8601()

  def http(headers) do
    case for({"if-modified-since", value} <- headers, do: value) do
      [] ->
        {:ok, nil}

      [value] ->
        case :httpd_util.convert_request_date(String.to_charlist(value)) do
          {{year, month, day}, {hour, minute, second}} ->
            year =
              if value =~ ~r/\A[A-Za-z]+, \d{2}-[A-Za-z]{3}-\d{2} /,
                do: rem(year, 100) + if(rem(year, 100) >= 69, do: 1900, else: 2000),
                else: year

            NaiveDateTime.new(year, month, day, hour, minute, second)

          _ ->
            {:ok, nil}
        end

      _ ->
        {:ok, nil}
    end
  rescue
    _ -> {:ok, nil}
  end
end
