defmodule Dawarich.ReleaseMigrations.Sync1160Test do
  use Dawarich.ScratchCase, async: true, group: :scratch_case_db
  alias Dawarich.ReleaseMigrations

  setup do
    scratch_sql!("""
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE TABLE countries(id bigserial PRIMARY KEY,name varchar,iso_a2 varchar,geom geometry(MultiPolygon,4326),updated_at timestamp);
    CREATE TABLE regions(id bigserial PRIMARY KEY,code varchar UNIQUE,geom geometry(MultiPolygon,4326),created_at timestamp,updated_at timestamp);
    """)

    :ok
  end

  test "released migration steps load generic disputed geometry and request exactly one full backfill" do
    module = ReleaseMigrations.find("1.16.0")
    assert module != nil

    steps =
      Map.new(module.steps(), fn step ->
        {v, f, _} = Dawarich.ReleaseMigration.normalize(step)
        {v, f}
      end)

    {_, noop} = hd(ReleaseMigrations.find("1.15.4").steps())
    assert noop.(ScratchRepo) == :ok
    steps["20261014120000"].(ScratchRepo)

    assert {:jobs, [{"DataMigrations::BackfillAchievementsJob", [], 0}]} =
             steps["20261014120100"].(ScratchRepo)

    assert [[count, true, true]] =
             rows(
               "SELECT count(*),bool_and(ST_SRID(geom)=4326 AND ST_IsValid(geom)),bool_and(ST_NPoints(geom)<=256) FROM disputed_areas"
             )

    assert count > 0

    assert [["GEOMETRY", 4326, 2]] =
             rows(
               "SELECT type,srid,coord_dimension FROM geometry_columns WHERE f_table_schema='public' AND f_table_name='disputed_areas'"
             )

    assert [[true]] =
             rows(
               "SELECT EXISTS(SELECT 1 FROM pg_indexes WHERE tablename='disputed_areas' AND indexdef LIKE '%USING gist (geom)%')"
             )

    [[id]] = rows("SELECT min(id) FROM disputed_areas")
    area = Dawarich.Achievements.DisputedArea.fetch!(ScratchRepo, id)
    assert {:ok, dumped} = Ecto.Type.dump(Dawarich.Achievements.DisputedArea.Geometry, area.geom)

    assert rows(
             "SELECT ST_Equals(geom,ST_GeomFromEWKB(decode($2,'hex'))) FROM disputed_areas WHERE id=$1",
             [id, dumped]
           ) == [[true]]

    assert area.geom.srid == 4326
  end

  test "boundary reload repairs only UA RU and publishes only with populated countries" do
    module = ReleaseMigrations.find("1.15.4")
    assert module != nil

    {_, fun, false} =
      module.steps()
      |> Enum.find(&(elem(&1, 0) == "20261013120000"))
      |> Dawarich.ReleaseMigration.normalize()

    assert fun.(ScratchRepo) == :ok

    scratch_sql!(
      "INSERT INTO countries(name,iso_a2,geom) SELECT code,code,ST_Multi(ST_MakeEnvelope(0,0,1,1,4326)) FROM unnest(ARRAY['UA','RU','DE']) code"
    )

    assert {:jobs, [{"DataMigrations::ReassignBoundaryPointsJob", [], 0}]} = fun.(ScratchRepo)

    assert [[true, true, true]] =
             rows(
               "SELECT bool_and(ST_XMax(geom)>20) FILTER(WHERE iso_a2='UA'),bool_and(ST_XMax(geom)>20) FILTER(WHERE iso_a2='RU'),bool_and(ST_XMax(geom)=1) FILTER(WHERE iso_a2='DE') FROM countries"
             )
  end

  test "region loads exclude and prune disputed subdivisions on every load" do
    scratch_sql!(
      "INSERT INTO regions(code,geom,created_at,updated_at) VALUES('UA-43',ST_Multi(ST_MakeEnvelope(0,0,1,1,4326)),now(),now())"
    )

    Dawarich.ReleaseMigrations.Effects.LoadRegions.run(ScratchRepo)

    assert rows("SELECT code FROM regions WHERE code=ANY($1)", [
             Dawarich.Achievements.Registry.disputed_subdivisions()
           ]) == []

    assert [[n]] = rows("SELECT count(*) FROM regions")
    assert n > 1000
  end

  defp rows(sql, params \\ []), do: ScratchRepo.query!(sql, params, log: false).rows
end
