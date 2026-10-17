defmodule Dawarich.Exports.Submission do
  @moduledoc false
  def parse(params) do
    with {:ok, format} <- file_format(params["file_format"]),
         {:ok, first, start_at} <- submission_time(params["start_at"]),
         {:ok, last, end_at} <- submission_time(params["end_at"]) do
      {:ok,
       %{
         name: "export_from_#{first}_to_#{last}.#{params["file_format"]}",
         file_format: format,
         start_at: start_at,
         end_at: end_at
       }}
    end
  rescue
    _ -> {:error, :invalid_submission}
  end

  defp file_format(value) when value in [nil, ""], do: {:ok, nil}
  defp file_format("json"), do: {:ok, 0}
  defp file_format("gpx"), do: {:ok, 1}
  defp file_format("archive"), do: {:ok, 2}
  defp file_format(_), do: {:error, :invalid_submission}

  defp submission_time(value) when is_binary(value) do
    if String.trim(value) == "" do
      {:ok, "", nil}
    else
      parts = Dawarich.Imports.DateParts.parse(value)
      %{"year" => year, "mon" => month, "mday" => day} = parts
      date = Date.new(year, month, day)
      julian = year < 1582 and month == 2 and day == 29 and rem(year, 4) == 0

      if (date == {:error, :invalid_date} and not julian) or
           (year == 1582 and month == 10 and day in 5..14),
         do: raise(ArgumentError, "invalid date")

      name =
        Enum.map_join([year, month, day], "-", fn n ->
          String.pad_leading(to_string(n), if(n == year, do: 4, else: 2), "0")
        end)

      time =
        try do
          zone = System.get_env("TIME_ZONE", "Europe/Berlin")
          epoch = Dawarich.Imports.ImportTime.parse(value, zone, DateTime.utc_now())

          {{y, m, d}, {h, min, sec}} =
            :calendar.gregorian_seconds_to_datetime(epoch + 62_167_219_200)

          struct!(NaiveDateTime, year: y, month: m, day: d, hour: h, minute: min, second: sec)
        rescue
          _ -> nil
        end

      {:ok, name, time}
    end
  end

  defp submission_time(_), do: {:error, :invalid_submission}
end
