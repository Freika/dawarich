defmodule Dawarich.EnhancedImport.PlaceWriterTest do
  use Dawarich.EnhancedImportCase

  alias Dawarich.EnhancedImport.PlaceWriter

  @written ~w(decimal_cast_waypoint name_over_limit tag_reuse_and_privacy writer_dedup
              zipped_single_entry waypoints_seen_zero)

  defp run(repo, import, items),
    do: Enum.reduce(items, PlaceWriter.new(import), &PlaceWriter.upsert(repo, &2, &1))

  test "every GPX fixture ends with Rails' places, tags and taggings" do
    for name <- @written do
      truncate!()
      fixture = load!(name)
      [import] = fixture["input"]["imports"]
      expected = fixture["expected"]

      state =
        run(
          ScratchRepo,
          %{id: import["id"], user_id: import["user_id"]},
          Enum.map(fixture["extracted"], &item/1)
        )

      assert places() == expected_places(expected), name
      assert tags() == expected_tags(expected), name
      assert taggings() == expected_taggings(expected), name

      assert state.count ==
               Map.get(expected["import"]["additional_data_extraction"]["counts"], "places", 0),
             name
    end
  end

  defp user! do
    [[user_id]] =
      rows(
        "INSERT INTO users (email, encrypted_password, created_at, updated_at) " <>
          "VALUES ('writer@example.test', '', now(), now()) RETURNING id"
      )

    user_id
  end

  defp tagged(external_id) do
    %{
      external_place_id: external_id,
      name: "Race",
      latitude: 51.3397,
      longitude: 12.3731,
      semantic_type: "Cafe",
      tag_name: "Cafe",
      tag_color: nil
    }
  end

  test "a repeated tagged waypoint is tagged once, as add_tag skips a present tag" do
    user_id = user!()

    state =
      run(ScratchRepo, %{id: 7, user_id: user_id}, [tagged("gpx:twice"), tagged("gpx:twice")])

    assert state.count == 2
    assert taggings() == [["Cafe", "Race", "POINT(12.3731 51.3397)", "Place"]]
  end

  test "a unique race on insert re-finds the row" do
    user_id = user!()
    place = tagged("gpx:race")

    HookRepo.set_hook(fn sql, _params ->
      if sql =~ "INSERT INTO places" and Process.put(:raced, true) == nil do
        rows(
          "INSERT INTO places (user_id, name, latitude, longitude, lonlat, source, geodata, created_at, updated_at) " <>
            "VALUES ($1, 'Other Writer', 51.3397, 12.3731, ST_SetSRID(ST_MakePoint(12.3731, 51.3397), 4326)::geography, " <>
            "2, '{\"external_place_id\": \"gpx:race\"}', now(), now())",
          [user_id]
        )
      end

      :ok
    end)

    state = run(HookRepo, %{id: 7, user_id: user_id}, [place])

    assert [[raced_id, "Other Writer"]] = rows("SELECT id, name FROM places")
    assert state.count == 1
    assert MapSet.member?(state.claimed, raced_id)
    assert taggings() == [["Cafe", "Other Writer", "POINT(12.3731 51.3397)", "Place"]]
  end
end
