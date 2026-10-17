defmodule Dawarich.UserData.Restore.Points do
  @moduledoc false
  alias Dawarich.UserData.Restore.{PointRefs, PointWriter}
  alias Dawarich.Imports.NormalCast.ArrayLiteral
  alias Dawarich.Ingest.Ruby

  def call(repo, user, data, context) do
    if Enumerable.impl_for(data) do
      refs = PointRefs.load(repo, user)

      columns =
        repo.query!(
          "SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='points'",
          [],
          log: false
        ).rows
        |> List.flatten()

      data
      |> Stream.filter(&valid?/1)
      |> Stream.map(&prepare(repo, user, &1, refs, columns, context))
      |> Stream.reject(&is_nil/1)
      |> Stream.chunk_every(5000)
      |> Enum.reduce({0, %{}}, fn batch, {count, cache} ->
        {created, cache} = PointWriter.write(repo, batch, cache, context)
        {count + created, cache}
      end)
      |> elem(0)
    else
      0
    end
  end

  defp valid?(row) when is_map(row) do
    Ruby.present?(row["timestamp"]) and
      ((is_binary(row["lonlat"]) and String.starts_with?(row["lonlat"], "POINT(")) or
         (Ruby.present?(row["longitude"]) and Ruby.present?(row["latitude"])))
  end

  defp valid?(_), do: false

  defp prepare(repo, user, row, refs, columns, context) do
    lonlat =
      if Ruby.blank?(row["lonlat"]),
        do: "POINT(#{Ruby.to_f(row["longitude"])} #{Ruby.to_f(row["latitude"])})",
        else: row["lonlat"]

    attrs =
      row
      |> Map.drop(
        ~w(created_at updated_at import_reference country_info visit_reference country longitude latitude anomaly)
      )
      |> Map.put("lonlat", lonlat)

    attrs =
      Enum.reduce(~w(inrids in_regions), attrs, fn key, acc ->
        if is_binary(acc[key]), do: Map.update!(acc, key, &ArrayLiteral.decode/1), else: acc
      end)

    attrs =
      Enum.reduce(~w(geodata raw_data), attrs, fn key, acc ->
        if is_binary(acc[key]), do: Map.update!(acc, key, &Jason.decode!/1), else: acc
      end)

    attrs =
      attrs
      |> Map.merge(%{"user_id" => user, "created_at" => context.now, "updated_at" => context.now})
      |> PointRefs.resolve(row, refs, context)

    attrs =
      if "altitude_decimal" in columns and Ruby.blank?(attrs["altitude_decimal"]) and
           Ruby.present?(attrs["altitude"]),
         do: Map.put(attrs, "altitude_decimal", attrs["altitude"]),
         else: attrs

    attrs = owned_refs(repo, user, attrs)
    Map.take(attrs, columns)
  rescue
    e in Dawarich.Imports.LeaseLost -> reraise e, __STACKTRACE__
    _ -> nil
  end

  defp owned_refs(repo, user, row) do
    Enum.reduce(
      [
        {"import_id", "imports"},
        {"visit_id", "visits"},
        {"track_id", "tracks"},
        {"raw_data_archive_id", "points_raw_data_archives"}
      ],
      row,
      fn {key, table}, acc ->
        if acc[key] &&
             repo.query!(
               "SELECT id FROM #{table} WHERE id=$1 AND user_id=$2",
               [Ruby.to_i(acc[key]), user],
               log: false
             ).rows == [],
           do: Map.put(acc, key, nil),
           else: acc
      end
    )
  end
end
