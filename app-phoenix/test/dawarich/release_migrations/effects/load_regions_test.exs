defmodule Dawarich.ReleaseMigrations.Effects.LoadRegionsTest do
  use Dawarich.ScratchCase

  alias Dawarich.RailsTree
  alias Dawarich.ReleaseMigrations.Effects.LoadRegions
  alias Dawarich.ReleaseMigrations.V1_15_2

  @app Path.expand("../../../..", __DIR__)
  @rails_asset "lib/assets/admin1_world.geojson"
  @old ~N[2026-01-01 00:00:00.000000]

  setup do
    scratch_sql!("""
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE TABLE countries (id bigserial PRIMARY KEY);
    CREATE TABLE regions (id bigserial PRIMARY KEY, code character varying NOT NULL, geom geometry(MULTIPOLYGON,4326) NOT NULL, created_at timestamp(6) NOT NULL, updated_at timestamp(6) NOT NULL);
    CREATE UNIQUE INDEX index_regions_on_code ON regions (code);
    """)

    :ok
  end

  test "loads every feature of the Rails asset and repairs the invalid ones exactly as Rails' two statements do" do
    LoadRegions.run(ScratchRepo)

    features = RailsTree.read(@rails_asset) |> Jason.decode!() |> Map.fetch!("features")
    codes = Enum.map(features, &get_in(&1, ["properties", "iso_3166_2"]))

    assert Enum.sort(column("SELECT code FROM regions")) == Enum.sort(codes)

    assert column("""
           SELECT count(*) FROM regions
           WHERE NOT ST_IsValid(geom) OR ST_SRID(geom) <> 4326 OR GeometryType(geom) <> 'MULTIPOLYGON'
           """) == [0]

    [[invalid, mismatched]] =
      ScratchRepo.query!(
        """
        WITH source AS (
          SELECT feature -> 'properties' ->> 'iso_3166_2' AS code,
                 ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(feature ->> 'geometry'), 4326)) AS geom
          FROM jsonb_array_elements($1::text::jsonb -> 'features') AS feature
        )
        SELECT count(*) FILTER (WHERE NOT ST_IsValid(source.geom)),
               count(*) FILTER (WHERE ST_AsEWKB(regions.geom) IS DISTINCT FROM ST_AsEWKB(
                 CASE WHEN ST_IsValid(source.geom) THEN source.geom
                      ELSE ST_Multi(ST_CollectionExtract(ST_MakeValid(source.geom), 3)) END))
        FROM source LEFT JOIN regions USING (code)
        """,
        [RailsTree.read(@rails_asset)],
        log: false
      ).rows

    assert invalid > 0
    assert mismatched == 0
  end

  test "a repeat run keeps ids, geometries and created_at, bumps updated_at and burns a sequence value per feature" do
    LoadRegions.run(ScratchRepo)
    before = snapshot()
    scratch_sql!("UPDATE regions SET updated_at = '2026-01-01 00:00:00'")

    LoadRegions.run(ScratchRepo)

    assert snapshot() == before
    assert column("SELECT count(*) FROM regions WHERE updated_at = '2026-01-01 00:00:00'") == [0]

    assert column("SELECT last_value FROM regions_id_seq") ==
             [2 * hd(column("SELECT count(*) FROM regions"))]
  end

  test "replaces a listed code's geometry and repairs an unlisted invalid row without touching its timestamps" do
    scratch_sql!("""
    INSERT INTO regions (code, geom, created_at, updated_at) VALUES
      ('DE-BE', ST_Multi(ST_GeomFromText('POLYGON((13 52, 14 52, 14 53, 13 53, 13 52))', 4326)), '2026-01-01', '2026-01-01'),
      ('ZZ-01', ST_Multi(ST_GeomFromText('POLYGON((0 0, 2 2, 2 0, 0 2, 0 0))', 4326)), '2026-01-01', '2026-01-01'),
      ('ZZ-02', ST_Multi(ST_GeomFromText('POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))', 4326)), '2026-01-01', '2026-01-01');
    """)

    LoadRegions.run(ScratchRepo)

    [[id, created_at, updated_at, moved]] =
      rows("""
      SELECT id, created_at, updated_at,
             NOT ST_Equals(geom, ST_GeomFromText('POLYGON((13 52, 14 52, 14 53, 13 53, 13 52))', 4326))
      FROM regions WHERE code = 'DE-BE'
      """)

    assert {id, created_at, moved} == {1, @old, true}
    assert NaiveDateTime.compare(updated_at, @old) == :gt

    assert rows("""
           SELECT updated_at, ST_AsEWKB(geom) = ST_AsEWKB(ST_Multi(ST_CollectionExtract(ST_MakeValid(
             ST_Multi(ST_GeomFromText('POLYGON((0 0, 2 2, 2 0, 0 2, 0 0))', 4326))), 3)))
           FROM regions WHERE code = 'ZZ-01'
           """) == [[@old, true]]

    assert rows("""
           SELECT updated_at, ST_AsEWKB(geom) = ST_AsEWKB(ST_Multi(ST_GeomFromText('POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))', 4326)))
           FROM regions WHERE code = 'ZZ-02'
           """) == [[@old, true]]
  end

  test "20260714224647 loads only when countries exist and the regions table is empty" do
    step("20260714224647").(ScratchRepo)
    assert column("SELECT count(*) FROM regions") == [0]

    scratch_sql!("""
    INSERT INTO countries DEFAULT VALUES;
    INSERT INTO regions (code, geom, created_at, updated_at) VALUES
      ('DE', ST_Multi(ST_GeomFromText('POLYGON((5 47, 15 47, 15 55, 5 55, 5 47))', 4326)), '2026-01-01', '2026-01-01');
    """)

    step("20260714224647").(ScratchRepo)
    assert column("SELECT code FROM regions") == ["DE"]

    scratch_sql!("DELETE FROM regions")
    step("20260714224647").(ScratchRepo)
    assert hd(column("SELECT count(*) FROM regions")) > 1000
  end

  test "20260720170000 deletes codes without a dash, then reloads over the subdivisions when countries exist" do
    scratch_sql!("""
    INSERT INTO regions (code, geom, created_at, updated_at) VALUES
      ('DE', ST_Multi(ST_GeomFromText('POLYGON((5 47, 15 47, 15 55, 5 55, 5 47))', 4326)), '2026-01-01', '2026-01-01'),
      ('ZZ-01', ST_Multi(ST_GeomFromText('POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))', 4326)), '2026-01-01', '2026-01-01');
    """)

    step("20260720170000").(ScratchRepo)
    assert column("SELECT code FROM regions") == ["ZZ-01"]

    scratch_sql!("""
    INSERT INTO countries DEFAULT VALUES;
    INSERT INTO regions (code, geom, created_at, updated_at) VALUES
      ('FR', ST_Multi(ST_GeomFromText('POLYGON((-5 42, 8 42, 8 51, -5 51, -5 42))', 4326)), '2026-01-01', '2026-01-01');
    """)

    step("20260720170000").(ScratchRepo)
    assert column("SELECT count(*) FROM regions WHERE code NOT LIKE '%-%'") == [0]
    assert column("SELECT id FROM regions WHERE code = 'ZZ-01'") == [2]
    assert hd(column("SELECT count(*) FROM regions")) > 1000
  end

  test "the release carries the Rails asset: priv links to it, and the image copies it in before mix release" do
    assert File.read_link!(Path.join(@app, "priv/admin1_world.geojson")) ==
             "../../lib/assets/admin1_world.geojson"

    assert LoadRegions.asset() == Application.app_dir(:dawarich, "priv/admin1_world.geojson")
    assert sha256(File.read!(LoadRegions.asset())) == sha256(RailsTree.read(@rails_asset))

    builder =
      RailsTree.read("docker/Dockerfile")
      |> String.split(~r/^FROM /m)
      |> Enum.find(&(&1 =~ ~r/\A\S+ AS phoenix_builder\n/))

    [before_release, _] = String.split(builder, "\nRUN mix release\n", parts: 2)

    assert "COPY lib/assets/admin1_world.geojson priv/admin1_world.geojson" in String.split(
             before_release,
             "\n"
           )

    assert "app-phoenix/priv/admin1_world.geojson" in String.split(
             RailsTree.read(".dockerignore"),
             "\n"
           )
  end

  defp step(version), do: V1_15_2.steps() |> List.keyfind(version, 0) |> elem(1)

  defp snapshot,
    do: rows("SELECT id, code, created_at, ST_AsEWKB(geom) FROM regions ORDER BY id")

  defp sha256(binary), do: :crypto.hash(:sha256, binary)
  defp rows(sql), do: ScratchRepo.query!(sql, [], log: false).rows
  defp column(sql), do: sql |> rows() |> List.flatten()
end
