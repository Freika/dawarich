defmodule Dawarich.ReleaseMigrations.LegacyDuplicatesTest do
  use Dawarich.ScratchCase, async: true, group: :scratch_case_db

  setup do
    scratch_sql!("""
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE TABLE users(id bigint PRIMARY KEY,points_count bigint);
    CREATE TABLE imports(id bigint PRIMARY KEY,points_count bigint);
    CREATE TABLE points(id bigserial PRIMARY KEY,user_id bigint,timestamp bigint,lonlat geography(Point,4326),longitude float,latitude float,raw_data jsonb,visit_id bigint,track_id bigint,import_id bigint);
    CREATE UNIQUE INDEX points_identity ON points(user_id,timestamp,lonlat);
    INSERT INTO users VALUES(1,4),(2,0);
    INSERT INTO imports VALUES(1,4),(2,0);
    """)

    :ok
  end

  test "legacy duplicate conversion preserves converted keeper metadata and floors user and import counters" do
    scratch_sql!("""
    INSERT INTO points(id,user_id,timestamp,lonlat,longitude,latitude,raw_data,visit_id,track_id,import_id) VALUES
      (10,1,100,ST_SetSRID(ST_MakePoint(1,2),4326),NULL,NULL,'{}',NULL,9,1),
      (11,1,100,NULL,1,2,'{"source":"first"}',7,8,1),
      (12,1,100,NULL,1,2,'{"source":"second"}',6,4,2),
      (13,1,200,NULL,3,4,NULL,NULL,NULL,1),
      (14,1,200,NULL,3,4,'{"oldest":true}',NULL,5,1),
      (15,1,300,NULL,NULL,2,NULL,NULL,NULL,1);
    """)

    {_, step, _} = hd(Dawarich.ReleaseMigrations.V1_10_1.steps())
    assert step.(ScratchRepo) == :ok

    assert rows("SELECT id,raw_data,visit_id,track_id FROM points ORDER BY id") == [
             [10, %{"source" => "first"}, 6, 9],
             [13, %{"oldest" => true}, nil, 5],
             [15, nil, nil, nil]
           ]

    assert rows("SELECT points_count FROM users WHERE id=1") == [[1]]
    assert rows("SELECT points_count FROM imports ORDER BY id") == [[2], [0]]

    assert rows("SELECT ST_X(lonlat::geometry),ST_Y(lonlat::geometry) FROM points WHERE id=13") ==
             [[3.0, 4.0]]

    assert step.(ScratchRepo) in [:ok, nil]
    scratch_sql!("ALTER TABLE points ADD COLUMN latitude float")
    assert step.(ScratchRepo) == :ok
    refute Dawarich.ReleaseMigration.column?(ScratchRepo, "points", "latitude")
  end

  defp rows(sql), do: ScratchRepo.query!(sql, [], log: false).rows
end
