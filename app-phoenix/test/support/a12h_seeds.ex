defmodule Dawarich.A12hSeeds do
  @moduledoc false

  @path Path.expand("../fixtures/a12e/seeds.json", __DIR__)
  @now ~N[2026-10-01 12:00:00]

  def now, do: @now

  def case!(name) do
    @path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("cases")
    |> Enum.find(&(&1["name"] == name))
  end

  def load!(repo, rows, tables) do
    Dawarich.FixtureCleanup.delete!(repo, tables)

    for table <- tables, row <- rows[table] || [] do
      repo.query!(
        "INSERT INTO #{table} SELECT * FROM jsonb_populate_record(NULL::#{table}, $1::jsonb)",
        [row],
        log: false
      )
    end

    for table <- tables do
      repo.query!(
        "SELECT setval(pg_get_serial_sequence($1,'id'), coalesce((SELECT max(id) FROM #{table}),0)+1,false)",
        [table],
        log: false
      )
    end

    :ok
  end

  def snapshot(repo, table) do
    columns =
      case table do
        "countries" ->
          "id,name,iso_a2,iso_a3,encode(ST_AsEWKB(ST_Normalize(geom)),'hex') AS geom,created_at,updated_at"

        "regions" ->
          "id,code,encode(ST_AsEWKB(ST_Normalize(geom)),'hex') AS geom,created_at,updated_at"

        _ ->
          "*"
      end

    [[json]] =
      repo.query!(
        "SELECT coalesce(json_agg(row_to_json(q)), '[]')::text FROM (SELECT #{columns} FROM #{table} ORDER BY id) q",
        [],
        log: false
      ).rows

    Jason.decode!(json)
  end

  def country_priv!(source) do
    dir = Path.join(System.tmp_dir!(), "a12h-countries-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "countries.geojson.gz"), :zlib.gzip(Jason.encode!(source)))
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end
end
