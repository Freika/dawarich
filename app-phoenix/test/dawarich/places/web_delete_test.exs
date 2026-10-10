defmodule Dawarich.Places.WebDeleteTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Places.WebDelete
  alias Dawarich.Test.{FrameSeeds, ApiGolden}

  @effects File.read!("test/fixtures/places/remaining/effects.json")
           |> Jason.decode!()
           |> Map.fetch!("effects")
  @tables ~w(places visits place_visits notes tags taggings)

  defp snapshot(id),
    do:
      Map.new(@tables, fn table ->
        {table,
         Repo.query!(
           "SELECT to_jsonb(t) FROM #{table} t WHERE id >= $1 AND id < $1+20 ORDER BY id",
           [id]
         ).rows
         |> List.flatten()}
      end)

  test "place deletion preserves visits and removes only its graph" do
    for entry <- @effects, entry["request"]["method"] == "delete" do
      user = FrameSeeds.seed_place_remainder!(entry)
      id = hd(entry["before"]["places"])["id"]
      before = snapshot(id)
      result = WebDelete.run(Repo, user, id, %{})

      if String.starts_with?(entry["name"], "foreign_") do
        assert result == {:error, :not_found}
        assert snapshot(id) == before
      else
        assert result == {:ok, id}
        after_rows = snapshot(id)

        assert after_rows["visits"] ==
                 Enum.map(before["visits"], fn row ->
                   if row["place_id"] == id, do: Map.put(row, "place_id", nil), else: row
                 end),
               entry["name"]

        for table <- ~w(places place_visits notes taggings) do
          key =
            case table do
              "places" -> "id"
              "place_visits" -> "place_id"
              "notes" -> "attachable_id"
              "taggings" -> "taggable_id"
            end

          assert after_rows[table] == Enum.reject(before[table], &(&1[key] == id)),
                 entry["name"] <> table
        end

        assert after_rows["tags"] == before["tags"]

        for table <- @tables do
          assert Enum.map(entry["after"][table], & &1["id"]) ==
                   Enum.map(after_rows[table], & &1["id"])
        end
      end
    end

    entry = Enum.find(@effects, &(&1["name"] == "show_html_false"))
    user = FrameSeeds.seed_place_remainder!(entry)
    id = hd(entry["before"]["places"])["id"]

    ApiGolden.insert!("action_text_rich_texts", %{
      "id" => id,
      "name" => "body",
      "record_type" => "Note",
      "record_id" => id,
      "body" => "<action-text-attachment></action-text-attachment>",
      "created_at" => "2026-10-02T10:00:00Z",
      "updated_at" => "2026-10-02T10:00:00Z"
    })

    before = snapshot(id)
    assert {:replay, _} = WebDelete.run(Repo, user, id, %{})
    assert snapshot(id) == before
    assert Repo.query!("SELECT id FROM action_text_rich_texts WHERE id=$1", [id]).rows == [[id]]
    assert commands() == []
  end
end
