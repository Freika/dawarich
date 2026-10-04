defmodule Dawarich.UserData.Export.Manifest do
  @moduledoc false
  @tables ~w(areas imports exports trips stats notifications visits tags tracks digests)
  @monthly ~w(points visits stats tracks digests)

  def write(repo, user, dir, entries, context) do
    counts =
      Enum.map(@tables, fn table ->
        [[count]] = repo.query!("SELECT count(*) FROM #{table} WHERE user_id=$1", [user]).rows
        {table, count}
      end)
      |> Map.new()

    [[points]] = repo.query!("SELECT points_count FROM users WHERE id=$1", [user]).rows

    [[places]] =
      repo.query!(
        "SELECT count(*) FROM places p JOIN visits v ON v.place_id=p.id WHERE v.user_id=$1",
        [user]
      ).rows

    [[archives]] =
      repo.query!("SELECT count(*) FROM points_raw_data_archives WHERE user_id=$1", [user]).rows

    counts =
      Map.merge(counts, %{
        "points" => points || 0,
        "places" => places,
        "raw_data_archives" => archives
      })

    order =
      ~w(areas imports exports trips stats notifications points visits places tags tracks digests raw_data_archives)

    files =
      Enum.map(@monthly, fn table ->
        {table,
         entries
         |> Enum.map(& &1.name)
         |> Enum.filter(&String.starts_with?(&1, table <> "/"))
         |> Enum.sort()}
      end)

    now =
      context.now
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()

    value = %Jason.OrderedObject{
      values: [
        {"format_version", 2},
        {"dawarich_version", Dawarich.AppVersion.current()},
        {"exported_at", now},
        {"counts", %Jason.OrderedObject{values: Enum.map(order, &{&1, counts[&1]})}},
        {"files", %Jason.OrderedObject{values: files}}
      ]
    }

    path = Path.join(dir, "manifest.json")
    File.write!(path, Jason.encode!(value, pretty: true))
    %{name: "manifest.json", path: path, count: counts}
  end
end
