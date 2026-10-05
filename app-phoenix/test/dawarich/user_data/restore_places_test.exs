defmodule Dawarich.UserData.RestorePlacesTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.UserDataSeeds
  alias Dawarich.UserData.Restore.{Places, Tags, Taggings}

  setup do
    rows("DELETE FROM countries WHERE id=988991")

    rows(
      "TRUNCATE places, areas, tags, taggings, visits, tracks, track_segments, digests, points_raw_data_archives CASCADE"
    )

    c = UserDataSeeds.seed!("v2", ScratchRepo)
    entries = UserDataSeeds.entries("export_UTC")

    data =
      Map.new(~w(places tags taggings), fn name ->
        {name,
         entries[name <> ".jsonl"] |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)}
      end)

    %{c: c, data: data}
  end

  for action <- [:create, :delete] do
    test "restore observes an identity #{action} committed while processing an earlier row", %{
      c: c
    } do
      assert_interleaving(c, unquote(action))
    end
  end

  test "restore preserves earlier inserts before a later NUL name", %{c: c} do
    valid = %{"name" => "before NUL", "latitude" => 1, "longitude" => 2}
    invalid = %{valid | "name" => "invalid" <> <<0>>}

    assert_raise Postgrex.Error, fn ->
      Places.call(ScratchRepo, c.user_id, [valid, invalid], c.context)
    end

    assert [[valid["name"]]] == rows("SELECT name FROM places WHERE name=$1", [valid["name"]])
  end

  for {field, value, error} <- [
        {"source", "invalid", ArgumentError},
        {"unknown_column", "invalid", KeyError}
      ] do
    test "restore reports earlier #{field} failure before a later NUL name", %{c: c} do
      first = %{
        "name" => "first invalid",
        "latitude" => 1,
        "longitude" => 2,
        unquote(field) => unquote(value)
      }

      later = %{"name" => "later" <> <<0>>, "latitude" => 1, "longitude" => 2}

      assert_raise unquote(error), fn ->
        Places.call(ScratchRepo, c.user_id, [first, later], c.context)
      end
    end
  end

  test "restore place batches reuse metadata with ordered identity reads and refresh changed schemas",
       %{
         c: c
       } do
    ref = make_ref()
    owner = self()

    :ok =
      :telemetry.attach(
        ref,
        [:dawarich, :scratch_repo, :query],
        fn _, _, metadata, _ ->
          if self() == owner do
            cond do
              String.contains?(metadata.query, "information_schema.columns") ->
                send(owner, {ref, :columns})

              String.contains?(metadata.query, "FROM places") ->
                send(owner, {ref, :identity})

              String.contains?(metadata.query, "FROM imports") ->
                send(owner, {ref, :import})

              true ->
                :ok
            end
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(ref) end)

    places =
      for n <- 1..3,
          do: %{"name" => "metadata-#{n}", "latitude" => n, "longitude" => n}

    assert Places.call(ScratchRepo, c.user_id, places, c.context) == 3
    assert_received {^ref, :columns}
    refute_received {^ref, :columns}
    for _ <- 1..3, do: assert_received({^ref, :identity})
    refute_received {^ref, :identity}
    refute_received {^ref, :import}

    rows("ALTER TABLE places ADD COLUMN loadtest_note text")

    try do
      place = %{
        "name" => "new column",
        "latitude" => 4,
        "longitude" => 4,
        "loadtest_note" => "fresh"
      }

      assert Places.call(ScratchRepo, c.user_id, [place], c.context) == 1
      assert [["fresh"]] == rows("SELECT loadtest_note FROM places WHERE name='new column'")
      assert_received {^ref, :columns}
      refute_received {^ref, :columns}
    after
      rows("ALTER TABLE places DROP COLUMN loadtest_note")
    end
  end

  test "restore place batch identities treat signed and rounded zero as one database value", %{
    c: c
  } do
    places =
      for lat <- [-0.0, 0.0, -0.0000004, 0.0000004],
          do: %{"name" => "same zero", "latitude" => lat, "longitude" => lat}

    assert Places.call(ScratchRepo, c.user_id, places, c.context) == 1
    assert Places.call(ScratchRepo, c.user_id, places, c.context) == 0
    assert [[1]] == rows("SELECT count(*) FROM places WHERE name='same zero'")
  end

  test "restore place batches preserve earlier inserts before invalid coordinates", %{c: c} do
    for {value, error, index} <- [
          {true, Dawarich.Ingest.Unsupported, 1},
          {10_000.0, Postgrex.Error, 2}
        ] do
      valid = %{"name" => "before failure #{index}", "latitude" => 1, "longitude" => 2}
      invalid = %{valid | "name" => "invalid #{index}", "latitude" => value}

      assert_raise error, fn ->
        Places.call(ScratchRepo, c.user_id, [valid, invalid], c.context)
      end

      assert [[valid["name"]]] ==
               rows("SELECT name FROM places WHERE name=$1", [valid["name"]])
    end
  end

  @tag :tmp_dir
  test "restore place batches tag identity and taggable references equal Rails", %{
    c: c,
    data: data,
    tmp_dir: dir
  } do
    assert Places.call(ScratchRepo, c.user_id, data["places"], c.context) ==
             c.expected["result"]["places_created"]

    assert Tags.call(ScratchRepo, c.user_id, data["tags"], c.context) ==
             c.expected["result"]["tags_created"]

    assert Taggings.call(ScratchRepo, c.user_id, data["taggings"], c.context) ==
             c.expected["result"]["taggings_created"]

    for {module, name} <- [
          {Dawarich.UserData.Export.Places, "places"},
          {Dawarich.UserData.Export.Tags, "tags"},
          {Dawarich.UserData.Export.Taggings, "taggings"}
        ] do
      [entry] = module.write(ScratchRepo, c.user_id, dir, c.context)

      actual =
        entry.path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

      actual =
        if name == "taggings",
          do:
            Enum.map(
              actual,
              &%{
                "name" => &1["taggable_name"],
                "tag" => &1["tag_name"],
                "type" => &1["taggable_type"]
              }
            ),
          else: actual

      assert actual == c.expected["rows"][name]
    end

    assert Places.call(ScratchRepo, c.user_id, data["places"], c.context) == 0
    assert Tags.call(ScratchRepo, c.user_id, data["tags"], c.context) == 0
    assert Taggings.call(ScratchRepo, c.user_id, data["taggings"], c.context) == 0
    place = hd(data["places"])
    variant = Map.put(place, "latitude", 50.123456)
    assert Places.call(ScratchRepo, c.user_id, [place, variant, variant], c.context) == 1

    assert [[2]] ==
             rows("SELECT count(*) FROM places WHERE user_id=$1 AND name=$2", [
               c.user_id,
               place["name"]
             ])

    boundary = Path.expand("../../fixtures/user_data/boundary_5001/entries/places.jsonl", __DIR__)
    stream = boundary |> File.stream!() |> Stream.map(&Jason.decode!/1)
    assert Places.call(ScratchRepo, c.user_id, stream, c.context) == 5001
    assert Places.call(ScratchRepo, c.user_id, stream, c.context) == 0

    zero = %{
      "name" => "zero",
      "latitude" => "nonnumeric",
      "longitude" => "0",
      "created_at" => "1990-01-01",
      "user_id" => 123
    }

    assert Places.call(ScratchRepo, c.user_id, [nil, zero], c.context) == 1

    assert [[c.user_id, "2026-10-02 12:00:00", "POINT(0 0)"]] ==
             rows(
               "SELECT user_id,to_char(created_at,'YYYY-MM-DD HH24:MI:SS'),ST_AsText(lonlat::geometry) FROM places WHERE name='zero'"
             )

    rounded =
      zero
      |> Map.put("name", "rounded")
      |> Map.put("latitude", 51.3000004)
      |> Map.put("longitude", 12.4000004)

    assert Places.call(ScratchRepo, c.user_id, [rounded], c.context) == 1

    assert [["POINT(12.4 51.3)"]] ==
             rows("SELECT ST_AsText(lonlat::geometry) FROM places WHERE name='rounded'")

    assert Places.call(
             ScratchRepo,
             c.user_id,
             [%{zero | "name" => String.duplicate("x", 256)}],
             c.context
           ) == 0

    assert Places.call(ScratchRepo, c.user_id, [%{zero | "name" => nil}], c.context) == 0
    assert Places.call(ScratchRepo, c.user_id, nil, c.context) == 0
    assert Tags.call(ScratchRepo, c.user_id, nil, c.context) == 0

    assert Tags.call(
             ScratchRepo,
             c.user_id,
             [
               %{"name" => "bad icon", "icon" => "letter"},
               %{"name" => "bad color", "color" => "red"},
               %{"name" => "bad radius", "privacy_radius_meters" => 5001}
             ],
             c.context
           ) == 0

    assert Tags.call(
             ScratchRepo,
             c.user_id,
             [%{"name" => "plain", "user_id" => 123}, %{"name" => "plain"}],
             c.context
           ) == 1

    assert [[c.user_id, false]] == rows("SELECT user_id,demo FROM tags WHERE name='plain'")

    suggested =
      zero
      |> Map.put("name", "Suggested place")
      |> Map.put("name_locked_at", "1990-01-01T00:00:00Z")

    assert Places.call(ScratchRepo, c.user_id, [suggested], c.context) == 1
    assert [[nil]] == rows("SELECT name_locked_at FROM places WHERE name='Suggested place'")

    assert Tags.call(
             ScratchRepo,
             c.user_id,
             [
               %{
                 "name" => "blank timestamps",
                 "created_at" => "",
                 "updated_at" => "",
                 "privacy_radius_meters" => ""
               }
             ],
             c.context
           ) == 1

    assert [["2026-10-02 12:00:00", nil]] ==
             rows(
               "SELECT to_char(created_at,'YYYY-MM-DD HH24:MI:SS'),privacy_radius_meters FROM tags WHERE name='blank timestamps'"
             )

    assert_raise KeyError, fn ->
      Places.call(
        ScratchRepo,
        c.user_id,
        [Map.put(zero, "name", "unknown") |> Map.put("removed_column", true)],
        c.context
      )
    end

    assert_raise ArgumentError, fn ->
      Places.call(
        ScratchRepo,
        c.user_id,
        [Map.put(zero, "name", "bad enum") |> Map.put("source", "other")],
        c.context
      )
    end

    assert [] == rows("SELECT command_type FROM job_outbox")
  end

  test "restore place import parent must be owned and cannot block victim deletion", %{
    c: c,
    data: data
  } do
    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES(988002,'parent-foreign@example.invalid',$1,$1)",
      [c.context.now]
    )

    rows(
      "INSERT INTO imports(id,user_id,name,created_at,updated_at) VALUES(988102,988002,'foreign parent',$1,$1),(988103,$2,'owned parent',$1,$1)",
      [c.context.now, c.user_id]
    )

    place = hd(data["places"])

    assert Places.call(ScratchRepo, c.user_id, [Map.put(place, "import_id", 988_102)], c.context) ==
             1

    assert [[nil]] == rows("SELECT import_id FROM places WHERE user_id=$1", [c.user_id])
    refute Dawarich.Imports.DestroyLease.foreign?(ScratchRepo, 988_102, 988_002)

    assert {:ok, :queued} ==
             Dawarich.Imports.Destroy.enqueue(ScratchRepo, 988_002, 988_102, c.context)

    owned = place |> Map.put("name", "owned parent place") |> Map.put("import_id", 988_103)
    assert Places.call(ScratchRepo, c.user_id, [owned], c.context) == 1
    assert [[988_103]] == rows("SELECT import_id FROM places WHERE name='owned parent place'")
    orphan = place |> Map.put("name", "orphan parent place") |> Map.put("import_id", 999_999)
    assert Places.call(ScratchRepo, c.user_id, [orphan], c.context) == 1
    assert [[nil]] == rows("SELECT import_id FROM places WHERE name='orphan parent place'")
  end

  test "restore unsupported or foreign tagging references do not attach", %{c: c, data: data} do
    assert Places.call(ScratchRepo, c.user_id, data["places"], c.context) == 1
    assert Tags.call(ScratchRepo, c.user_id, data["tags"], c.context) == 1
    tagging = hd(data["taggings"])

    assert Taggings.call(
             ScratchRepo,
             c.user_id,
             Enum.map(["Trip", "Area", "place", "", nil], &Map.put(tagging, "taggable_type", &1)),
             c.context
           ) == 0

    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES(988002,'tag-foreign@example.invalid',$1,$1)",
      [c.context.now]
    )

    assert Tags.call(ScratchRepo, 988_002, [%{"name" => "foreign"}], c.context) == 1

    assert Places.call(
             ScratchRepo,
             988_002,
             [%{"name" => "foreign", "latitude" => 10, "longitude" => 20}],
             c.context
           ) == 1

    foreign_tag = Map.put(tagging, "tag_name", "foreign")

    foreign_place =
      tagging
      |> Map.put("taggable_name", "foreign")
      |> Map.put("taggable_latitude", 10)
      |> Map.put("taggable_longitude", 20)

    assert Taggings.call(
             ScratchRepo,
             c.user_id,
             [foreign_tag, foreign_place, nil, %{}, Map.put(tagging, "taggable_latitude", nil)],
             c.context
           ) == 0

    nearby =
      tagging
      |> Map.put("taggable_name", "changed archive name")
      |> Map.update!("taggable_latitude", &(Dawarich.Ingest.Ruby.to_f(&1) + 0.00005))

    assert Taggings.call(ScratchRepo, c.user_id, [nearby, tagging], c.context) == 1

    assert [["Place", c.user_id, c.user_id]] ==
             rows(
               "SELECT t.taggable_type,p.user_id,g.user_id FROM taggings t JOIN places p ON p.id=t.taggable_id JOIN tags g ON g.id=t.tag_id"
             )

    assert Taggings.call(ScratchRepo, c.user_id, data["taggings"], c.context) == 0
    assert Taggings.call(ScratchRepo, c.user_id, nil, c.context) == 0
  end

  defp assert_interleaving(c, action) do
    later = %{"name" => "concurrent identity", "latitude" => 1, "longitude" => 2}
    earlier = %{later | "name" => "earlier identity"}
    if action == :delete, do: Places.call(ScratchRepo, c.user_id, [later], c.context)
    ref = make_ref()
    owner = self()
    Process.put(ref, true)

    :ok =
      :telemetry.attach(
        ref,
        [:dawarich, :scratch_repo, :query],
        fn _, _, metadata, _ ->
          if self() == owner and String.starts_with?(metadata.query, "INSERT INTO places") and
               Process.delete(ref) do
            Task.async(fn ->
              case action do
                :create -> Places.call(ScratchRepo, c.user_id, [later], c.context)
                :delete -> rows("DELETE FROM places WHERE name=$1", [later["name"]])
              end
            end)
            |> Task.await()
          end
        end,
        nil
      )

    try do
      assert Places.call(ScratchRepo, c.user_id, [earlier, later], c.context) ==
               if(action == :create, do: 1, else: 2)

      assert [[1]] == rows("SELECT count(*) FROM places WHERE name=$1", [later["name"]])
    after
      :telemetry.detach(ref)
      Process.delete(ref)
    end
  end
end
