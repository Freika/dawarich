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

  defp pins!(pins) do
    truncate!()
    user_id = user!()

    for {id, name} <- pins do
      rows(
        "INSERT INTO places (user_id, name, latitude, longitude, lonlat, source, geodata, created_at, updated_at) " <>
          "VALUES ($1, $2, 51.3397, 12.3731, ST_SetSRID(ST_MakePoint(12.3731, 51.3397), 4326)::geography, " <>
          "2, jsonb_build_object('external_place_id', $3::text), now(), now())",
        [user_id, name, id]
      )
    end

    %{id: 7, user_id: user_id}
  end

  defp pin(id, name, tag), do: %{tagged(id) | name: name, semantic_type: tag, tag_name: tag}

  test "a prefetched chunk ends as one-by-one writes do" do
    cases = [
      {[{"gpx:old", "Old"}], [pin("gpx:new", "New", nil), pin("gpx:old", "Old", nil)]},
      {[{"gpx:one", "One"}, {"gpx:two", "Two"}],
       [pin("gpx:dup", nil, "Cafe"), pin("gpx:two", "Two", nil), pin("gpx:dup", nil, "Cafe")]},
      {[{nil, "Cafe"}, {"gpx:r2", "Other"}],
       [pin("gpx:x", "Cafe", "Cafe"), pin("gpx:x", "Cafe", "Cafe")]}
    ]

    for {pins, items} <- cases do
      one_by_one = run(ScratchRepo, pins!(pins), items)
      expected = {places(), taggings(), one_by_one.count}

      state = PlaceWriter.prefetch(ScratchRepo, PlaceWriter.new(pins!(pins)), items)
      chunked = Enum.reduce(items, state, &PlaceWriter.upsert(ScratchRepo, &2, &1))

      assert {places(), taggings(), chunked.count} == expected, inspect(pins)
    end
  end

  test "renamed and nearby lookups never walk the user's places when statistics are stale" do
    user_id = user!()
    pin = "ST_SetSRID(ST_MakePoint(12.3505, 51.3005), 4326)::geography"

    grid =
      "ST_SetSRID(ST_MakePoint(12.3 + (g % 100) * 0.001, 51.3 + (g / 100) * 0.001), 4326)::geography"

    {:error, plans} =
      ScratchRepo.transaction(fn ->
        rows(
          "INSERT INTO places (user_id, name, latitude, longitude, lonlat, source, geodata, created_at, updated_at) " <>
            "SELECT 1000000 + g, 'Other', 51.3, 12.3, #{pin}, 2, '{}', now(), now() " <>
            "FROM generate_series(1, 2000) g"
        )

        rows("ANALYZE places")

        rows(
          "INSERT INTO places (user_id, name, latitude, longitude, lonlat, source, geodata, created_at, updated_at) " <>
            "SELECT $1, 'Mine', 51.3, 12.3, #{grid}, 2, jsonb_build_object('external_place_id', 'gpx:' || g), " <>
            "now(), now() FROM generate_series(1, 500) g",
          [user_id]
        )

        HookRepo.set_hook(fn sql, params ->
          if sql =~ "ST_DWithin",
            do:
              send(
                self(),
                {:plan, rows("EXPLAIN " <> sql, params) |> List.flatten() |> Enum.join("\n")}
              )

          :ok
        end)

        place = %{tagged("gpx:fresh") | latitude: 51.3005, longitude: 12.3505, tag_name: nil}
        run(HookRepo, %{id: 7, user_id: user_id}, [place])
        ScratchRepo.rollback(plans())
      end)

    assert length(plans) == 2
    refute Enum.any?(plans, &(&1 =~ "index_places_on_user_id")), Enum.join(plans, "\n\n")
  end

  test "renamed and nearby lookups use the lonlat index when other places are spread out" do
    user_id = user!()

    grid =
      "ST_SetSRID(ST_MakePoint(12.3 + (g % 100) * 0.001, 51.3 + (g / 100) * 0.001), 4326)::geography"

    {:error, plans} =
      ScratchRepo.transaction(fn ->
        rows(
          "INSERT INTO places (user_id, name, latitude, longitude, lonlat, source, geodata, created_at, updated_at) " <>
            "SELECT 1000000 + g, 'Other', 51.3, 12.3, #{grid}, 2, '{}', now(), now() " <>
            "FROM generate_series(1, 2000) g"
        )

        rows("ANALYZE places")

        rows(
          "INSERT INTO places (user_id, name, latitude, longitude, lonlat, source, geodata, created_at, updated_at) " <>
            "SELECT $1, 'Mine', 51.3, 12.3, #{grid}, 2, jsonb_build_object('external_place_id', 'gpx:' || g), " <>
            "now(), now() FROM generate_series(1, 500) g",
          [user_id]
        )

        HookRepo.set_hook(fn sql, params ->
          if sql =~ "ST_DWithin",
            do:
              send(
                self(),
                {:plan, rows("EXPLAIN " <> sql, params) |> List.flatten() |> Enum.join("\n")}
              )

          :ok
        end)

        place = %{tagged("gpx:fresh") | latitude: 51.3005, longitude: 12.3505, tag_name: nil}
        run(HookRepo, %{id: 7, user_id: user_id}, [place])
        ScratchRepo.rollback(plans())
      end)

    assert length(plans) == 2
    refute Enum.any?(plans, &(&1 =~ "index_places_on_user_id")), Enum.join(plans, "\n\n")
    assert Enum.all?(plans, &(&1 =~ "index_places_on_lonlat")), Enum.join(plans, "\n\n")
  end

  defp plans do
    receive do
      {:plan, plan} -> [plan | plans()]
    after
      0 -> []
    end
  end
end
