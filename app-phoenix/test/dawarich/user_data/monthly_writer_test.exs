defmodule Dawarich.UserData.MonthlyWriterTest do
  use ExUnit.Case, async: true
  alias Dawarich.UserData.Export.{Monthly, Serializer}

  @tag :tmp_dir
  test "monthly batches remain bounded and byte-identical to the legacy writer", %{tmp_dir: dir} do
    rows =
      for n <- 1..1003 do
        {Enum.at(["2026-01", "2025-12", "unknown"], rem(n, 3)),
         [{"timestamp", n}, {"text", "雪 <>&\n"}, {"missing", nil}]}
      end

    legacy = legacy_write(rows, Path.join(dir, "legacy"))
    output = Path.join(dir, "output")
    path = Path.join(output, "points/2026/2026-01.jsonl")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "stale")
    key = make_ref()
    Process.put(key, [])

    stream =
      rows
      |> Stream.with_index(1)
      |> Stream.map(fn {row, n} ->
        if n in [4, 1001], do: Process.put(key, Process.get(key) ++ [File.read!(path)])
        row
      end)

    entries = Monthly.write_rows(stream, "points", output)

    first_batch =
      rows
      |> Enum.take(1000)
      |> Enum.filter(&(elem(&1, 0) == "2026-01"))
      |> Enum.map_join(fn {_, pairs} -> encode(pairs) end)

    assert {Process.delete(key), snapshot(entries)} ==
             {["stale", first_batch], snapshot(legacy)}
  end

  defp legacy_write(rows, dir) do
    rows
    |> Enum.reduce(%{}, fn {month, pairs}, entries ->
      year = month |> String.split("-") |> hd()
      name = "points/#{year}/#{month}.jsonl"
      path = Path.join(dir, name)

      unless entries[name] do
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, "")
      end

      File.write!(path, encode(pairs), [:append])
      Map.update(entries, name, %{name: name, path: path, count: 1}, &%{&1 | count: &1.count + 1})
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.name)
  end

  defp encode(pairs), do: Serializer.encode(%Jason.OrderedObject{values: pairs}) <> "\n"

  defp snapshot(entries),
    do: Enum.map(entries, &{&1.name, &1.count, File.read!(&1.path), Enum.sort(Map.keys(&1))})
end
