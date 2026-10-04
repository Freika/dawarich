defmodule Dawarich.UserData.Export.Taggings do
  @moduledoc false
  alias Dawarich.UserData.Export.Serializer
  alias Dawarich.RailsTime

  @tables %{
    "Place" => "places",
    "Area" => "areas",
    "Trip" => "trips",
    "Visit" => "visits",
    "Import" => "imports",
    "Tag" => "tags",
    "Export" => "exports"
  }

  def write(repo, user, dir, context) do
    rows =
      RailsTime.with_zone(repo, context.zone, fn ->
        repo.query!(
          "SELECT t.name,g.taggable_type,#{RailsTime.sql("g.created_at", 3)},#{RailsTime.sql("g.updated_at", 3)},g.taggable_id FROM tags t JOIN taggings g ON g.tag_id=t.id WHERE t.user_id=$1 ORDER BY t.id,g.id",
          [user]
        ).rows
      end)

    path = Path.join(dir, "taggings.jsonl")

    File.open!(path, [:write, :binary], fn io ->
      Enum.each(rows, fn [name, type, created, updated, id] ->
        base = [
          {"tag_name", name},
          {"taggable_type", type},
          {"created_at", created},
          {"updated_at", updated}
        ]

        pairs = base ++ taggable(repo, user, type, id)
        :ok = IO.binwrite(io, [Serializer.encode(%Jason.OrderedObject{values: pairs}), "\n"])
      end)
    end)

    [%{name: "taggings.jsonl", path: path, count: length(rows), attachments: []}]
  end

  defp taggable(repo, user, type, id) do
    table = Map.fetch!(@tables, type)
    columns = Serializer.columns(repo, table, [])
    names = Enum.map(columns, &elem(&1, 0))

    select =
      Enum.map_join(~w(name latitude longitude), ",", fn name ->
        if name in names, do: ~s("#{name}"), else: "NULL"
      end)

    case repo.query!("SELECT #{select} FROM #{table} WHERE id=$1 AND user_id=$2", [id, user]).rows do
      [] ->
        []

      [[name, lat, lon]] ->
        [
          {"taggable_name", name},
          {"taggable_latitude", coordinate(lat)},
          {"taggable_longitude", coordinate(lon)}
        ]
    end
  end

  defp coordinate(nil), do: nil
  defp coordinate(%Decimal{} = value), do: Serializer.value("", "", "numeric", value)

  defp coordinate(value) when is_float(value),
    do: Dawarich.ReleaseMigrations.Effects.Support.RubyFloat.to_s(value)

  defp coordinate(value), do: to_string(value)
end
