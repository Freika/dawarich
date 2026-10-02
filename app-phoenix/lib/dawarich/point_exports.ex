defmodule Dawarich.PointExports do
  @moduledoc false

  alias Dawarich.{RailsCommands, Repo}

  @formats %{"json" => 0, "gpx" => 1}
  @stamp ~r/\A(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2}) (?:UTC|([+-])(\d{2})(\d{2}))\z/

  def parse(%{"start_at" => start_at, "end_at" => end_at, "file_format" => format})
      when is_map_key(@formats, format) do
    with {:ok, start_date, start_utc} <- stamp(start_at),
         {:ok, end_date, end_utc} <- stamp(end_at) do
      {:ok,
       %{
         name: "export_from_#{start_date}_to_#{end_date}.#{format}",
         file_format: Map.fetch!(@formats, format),
         start_at: start_utc,
         end_at: end_utc
       }}
    end
  end

  def parse(_params), do: :rails

  def create(export, user_id, locale, repo \\ Repo) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :microsecond)

    repo.transaction(fn ->
      %{rows: [[id]]} =
        repo.query!(
          """
          INSERT INTO exports (name, status, file_format, file_type, start_at, end_at, user_id, created_at, updated_at)
          VALUES ($1, 0, $2, 0, $3, $4, $5, $6, $6)
          RETURNING id
          """,
          [export.name, export.file_format, export.start_at, export.end_at, user_id, now],
          log: false
        )

      RailsCommands.insert!(repo, "exports.points_created", %{
        "export_id" => id,
        "user_id" => user_id,
        "locale" => locale
      })

      id
    end)
  rescue
    error -> {:error, "export write failed: " <> inspect(error.__struct__)}
  end

  defp stamp(value) when is_binary(value) do
    case Regex.run(@stamp, value, capture: :all_but_first) do
      [year, month, day, hour, minute, second | offset] ->
        with year when year >= 1583 <- String.to_integer(year),
             {:ok, date} <- Date.new(year, String.to_integer(month), String.to_integer(day)),
             {:ok, time} <-
               Time.new(
                 String.to_integer(hour),
                 String.to_integer(minute),
                 String.to_integer(second)
               ),
             {:ok, seconds} <- offset(offset) do
          {:ok, Date.to_iso8601(date),
           NaiveDateTime.add(NaiveDateTime.new!(date, time), -seconds)}
        else
          _ -> :rails
        end

      nil ->
        :rails
    end
  end

  defp stamp(_value), do: :rails

  defp offset([]), do: {:ok, 0}

  defp offset([sign, hours, minutes]) do
    case {String.to_integer(hours), String.to_integer(minutes)} do
      {h, m} when h <= 23 and m <= 59 ->
        {:ok, if(sign == "-", do: -1, else: 1) * (h * 3600 + m * 60)}

      _ ->
        :rails
    end
  end
end
