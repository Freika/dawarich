defmodule Dawarich.UserData.Export.Monthly do
  @moduledoc false
  alias Dawarich.UserData.Export.Serializer

  def write(repo, user, table, dir, context, excluded, month, transform) do
    columns = Serializer.columns(repo, table, excluded)

    rows =
      Serializer.pages(repo, user, table, columns, context.zone, [month])
      |> Stream.map(fn [id | values] ->
        {values, [key]} = Enum.split(values, length(columns))

        pairs =
          Enum.zip_with(columns, values, fn {name, type}, value ->
            {name, Serializer.value(table, name, type, value)}
          end)

        {key || "unknown", transform.(id, pairs)}
      end)

    write_rows(rows, table, dir)
  end

  def write_rows(rows, table, dir) do
    entries =
      Enum.reduce(rows, %{}, fn {month, pairs}, entries ->
        year = month |> String.split("-") |> hd()
        name = "#{table}/#{year}/#{month}.jsonl"
        path = Path.join(dir, name)

        case entries[name] do
          nil ->
            File.mkdir_p!(Path.dirname(path))
            File.write!(path, "")

          _ ->
            :ok
        end

        File.write!(path, [Serializer.encode(%Jason.OrderedObject{values: pairs}), "\n"], [
          :append
        ])

        Map.update(
          entries,
          name,
          %{name: name, path: path, count: 1},
          &%{&1 | count: &1.count + 1}
        )
      end)

    entries |> Map.values() |> Enum.sort_by(& &1.name)
  end

  def timestamp_month(column), do: "to_char(t.#{column},'YYYY-MM')"

  def calendar_month,
    do:
      "CASE WHEN t.year IS NULL OR t.month IS NULL THEN NULL ELSE lpad(t.year::text,4,'0')||'-'||lpad(t.month::text,2,'0') END"
end
