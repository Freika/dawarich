defmodule Dawarich.UserData.ExportEntitiesTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.UserDataSeeds

  alias Dawarich.UserData.Export.{
    Settings,
    Areas,
    Imports,
    Exports,
    Trips,
    Notifications,
    Tags,
    Taggings
  }

  @modules [
    {Settings, "settings"},
    {Areas, "areas"},
    {Imports, "imports"},
    {Exports, "exports"},
    {Trips, "trips"},
    {Notifications, "notifications"},
    {Tags, "tags"},
    {Taggings, "taggings"}
  ]

  setup do
    rows("DELETE FROM countries WHERE id=988991")

    rows(
      "TRUNCATE places, areas, tags, taggings, visits, tracks, track_segments, digests, points_raw_data_archives CASCADE"
    )

    :ok
  end

  @tag :tmp_dir
  test "backup standalone JSONL entities equal Rails bytes", %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("UTC", ScratchRepo)
    context = Map.put(c.context, :application_zone, "Europe/Berlin")
    expected = UserDataSeeds.entries("export_UTC")

    for {module, name} <- @modules do
      [entry] = module.write(ScratchRepo, c.user_id, dir, context)
      assert entry.name == name <> ".jsonl"
      assert File.read!(entry.path) == expected[entry.name], name
      assert entry.count == length(String.split(expected[entry.name], "\n", trim: true))
    end

    settings = File.read!(Path.join(dir, "settings.jsonl")) |> Jason.decode!()
    assert Map.has_key?(settings, "immich_api_key")
    assert settings["immich_api_key"] == nil
    assert settings["gps_filtering_enabled"] == false
    assert File.read!(Path.join(dir, "notifications.jsonl")) =~ ~S(\u003ctitle\u003e\u0026)

    for zone <- ["Europe/Berlin", "America/New_York"] do
      rows(
        "UPDATE users SET settings=jsonb_set(settings,'{timezone}',to_jsonb($1::text)) WHERE id=$2",
        [zone, c.user_id]
      )

      hour = if zone == "Europe/Berlin", do: "140000", else: "080000"

      rows("UPDATE exports SET name=$1 WHERE id=$2", [
        "user_data_export_20261002_" <> hour <> ".zip",
        c.export_id
      ])

      expected = UserDataSeeds.entries("export_" <> String.replace(zone, "/", "_"))

      for {module, name} <- @modules do
        [entry] = module.write(ScratchRepo, c.user_id, dir, %{context | zone: zone})
        assert File.read!(entry.path) == expected[name <> ".jsonl"], name <> " " <> zone
      end
    end

    rows(
      "UPDATE trips SET path=ST_GeomFromText('LINESTRING(12.4 51.3,12.5 51.4)',4326) WHERE user_id=$1",
      [c.user_id]
    )

    [entry] = Trips.write(ScratchRepo, c.user_id, dir, context)

    [trip] =
      File.read!(entry.path) |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    assert trip["path"] == "LINESTRING (12.4 51.3, 12.5 51.4)"
  end

  @tag :tmp_dir
  test "backup excludes another user's rows and private identifiers", %{tmp_dir: dir} do
    c = UserDataSeeds.seed!("UTC", ScratchRepo)

    for table <- ~w(areas imports exports trips notifications tags) do
      [[id]] = rows("SELECT min(id) FROM #{table} WHERE user_id=$1", [c.user_id])

      rows(
        "INSERT INTO #{table} SELECT (jsonb_populate_record(NULL::#{table},to_jsonb(t)||jsonb_build_object('id',id+100000,'user_id',988002,'name','foreign synthetic','title','foreign synthetic'))).* FROM #{table} t WHERE id=$1",
        [id]
      )
    end

    rows(
      "INSERT INTO taggings(id,tag_id,taggable_type,taggable_id,created_at,updated_at) VALUES(1088711,1088701,'Place',988501,$1,$1)",
      [~N[2026-10-02 12:00:00]]
    )

    expected = UserDataSeeds.entries("export_UTC")

    for {module, name} <- @modules do
      [entry] =
        module.write(
          ScratchRepo,
          c.user_id,
          dir,
          Map.put(c.context, :application_zone, "Europe/Berlin")
        )

      bytes = File.read!(entry.path)
      assert bytes == expected[name <> ".jsonl"], name
      refute bytes =~ "foreign synthetic"

      for line <- String.split(bytes, "\n", trim: true) do
        row = Jason.decode!(line)
        refute Map.has_key?(row, "user_id")
        refute Map.has_key?(row, "id")
      end
    end
  end
end
