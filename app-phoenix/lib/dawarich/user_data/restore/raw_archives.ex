defmodule Dawarich.UserData.Restore.RawArchives do
  @moduledoc false
  alias Dawarich.UserData.Restore.{Batch, Files}
  alias Dawarich.Ingest.Ruby

  def call(repo, user, data, directory, context) when is_list(data) do
    columns =
      repo.query!(
        "SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='points_raw_data_archives'",
        [],
        log: false
      ).rows
      |> List.flatten()

    Enum.reduce(data, [0, 0], fn row, [created, files] ->
      case restore(repo, user, row, columns, directory, context) do
        nil -> [created, files]
        file -> [created + 1, files + if(file, do: 1, else: 0)]
      end
    end)
  end

  def call(_, _, _, _, _), do: [0, 0]

  defp restore(repo, user, row, columns, directory, context) when is_map(row) do
    if Ruby.present?(row["file_error"]) do
      nil
    else
      attrs = row |> Map.take(columns) |> Map.drop(~w(id user_id)) |> Map.put("user_id", user)

      attrs =
        Enum.reduce(~w(created_at updated_at), attrs, fn key, acc ->
          if Ruby.blank?(acc[key]), do: Map.put(acc, key, context.now), else: acc
        end)

      cast = Batch.row!(repo, "points_raw_data_archives", attrs, context)

      if valid?(cast) and
           repo.query!(
             "SELECT id FROM points_raw_data_archives WHERE user_id=$1 AND year=$2 AND month=$3 AND chunk_number=$4 LIMIT 1",
             [user, cast["year"], cast["month"], cast["chunk_number"]],
             log: false
           ).rows == [] do
        id = Batch.create_record!(repo, "points_raw_data_archives", attrs, context)
        row = Map.put(row, "content_type", row["content_type"] || "application/gzip")
        Files.restore(repo, "Points::RawDataArchive", id, row, directory, context)
      end
    end
  end

  defp restore(_, _, _, _, _, _), do: nil

  defp valid?(row) do
    numbers = ~w(year month chunk_number point_count)

    Enum.all?(numbers, &is_integer(row[&1])) and row["year"] in 1971..2099 and
      row["month"] in 1..12 and row["chunk_number"] > 0 and row["point_count"] > 0 and
      Ruby.present?(row["point_ids_checksum"]) and valid_metadata?(row["metadata"])
  end

  defp valid_metadata?(value) when is_map(value) do
    Ruby.blank?(value["format_version"]) or Ruby.to_i(value["format_version"]) < 2 or
      (Ruby.present?(value["expected_count"]) and Ruby.present?(value["actual_count"]))
  end

  defp valid_metadata?(value), do: Ruby.blank?(value)
end
