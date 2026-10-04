defmodule Dawarich.UserData.Restore.Taggings do
  @moduledoc false
  alias Dawarich.Ingest.Ruby
  alias Dawarich.Imports.NormalCast.Text
  alias Dawarich.UserData.Restore.{Batch, Places}

  def call(repo, user, data, context) when is_list(data) do
    Enum.reduce(data, 0, fn row, count -> count + restore(repo, user, row, context) end)
  end

  def call(_, _, _, _), do: 0

  defp restore(repo, user, row, context) when is_map(row) do
    with true <- row["taggable_type"] == "Place",
         true <- Ruby.present?(row["tag_name"]) and Ruby.present?(row["taggable_name"]),
         [[tag]] <-
           repo.query!(
             "SELECT id FROM tags WHERE user_id=$1 AND name=$2 LIMIT 1",
             [user, Text.cast(row["tag_name"])],
             log: false
           ).rows,
         {lat, lon} <- Places.coordinates(row, "taggable_latitude", "taggable_longitude"),
         [[place]] <- find_place(repo, user, row["taggable_name"], lat, lon),
         [] <-
           repo.query!(
             "SELECT id FROM taggings WHERE tag_id=$1 AND taggable_type='Place' AND taggable_id=$2 LIMIT 1",
             [tag, place],
             log: false
           ).rows do
      Batch.create!(
        repo,
        "taggings",
        %{
          "tag_id" => tag,
          "taggable_type" => "Place",
          "taggable_id" => place,
          "created_at" => context.now,
          "updated_at" => context.now
        },
        context
      )
    else
      _ -> 0
    end
  end

  defp restore(_, _, _, _), do: 0

  defp find_place(repo, user, name, lat, lon) do
    case Places.find(repo, user, name, lat, lon) do
      [] ->
        repo.query!(
          "SELECT id FROM places WHERE user_id=$1 AND latitude BETWEEN $2 AND $3 AND longitude BETWEEN $4 AND $5 ORDER BY id LIMIT 1",
          [
            user,
            Decimal.from_float(lat - 0.0001),
            Decimal.from_float(lat + 0.0001),
            Decimal.from_float(lon - 0.0001),
            Decimal.from_float(lon + 0.0001)
          ],
          log: false
        ).rows

      found ->
        found
    end
  end
end
