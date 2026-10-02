defmodule Dawarich.Imports.GpxNumericPersistenceTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.GpxImporter
  @oracle Path.expand("../../fixtures/gpx/rails_numeric_persistence_oracle.json", __DIR__)
  @cases @oracle |> File.read!() |> Jason.decode!()

  setup do
    [[user]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES ('numeric@example.test',now(),now()) RETURNING id"
      )

    [[id]] =
      rows(
        "INSERT INTO imports(user_id,name,source,created_at,updated_at) VALUES ($1,'numeric.gpx',4,now(),now()) RETURNING id",
        [user]
      )

    path = Path.join(System.tmp_dir!(), "gpx-numeric-#{System.unique_integer([:positive])}.gpx")

    on_exit(fn ->
      File.rm(path)
      rows("DELETE FROM imports WHERE id=$1", [id])
    end)

    %{
      import: %{id: id, user_id: user, name: "numeric.gpx"},
      path: path,
      ctx: %{
        repo: ScratchRepo,
        now: ~U[2026-01-15 23:30:00Z],
        zone: "Europe/Berlin",
        locale: "de",
        altitude_decimal?: true
      }
    }
  end

  for example <- @cases do
    @example example
    test "actual Rails persisted numeric behavior: #{example["name"]}", c do
      e = @example
      ext = if e["speed"], do: "<extensions><speed>#{e["speed"]}</speed></extensions>", else: ""

      File.write!(
        c.path,
        "<gpx><trk><trkseg><trkpt lon='#{e["lon"]}' lat='#{e["lat"]}'><ele>#{e["ele"]}</ele><time>2024-03-16T12:30:23Z</time>#{ext}</trkpt></trkseg></trk></gpx>"
      )

      assert :ok == GpxImporter.call(c.path, c.import, c.ctx)

      assert [[e["raw_points"], e["doubles"], e["processed"]]] ==
               rows("SELECT raw_points,doubles,processed FROM imports WHERE id=$1", [c.import.id])

      actual =
        rows("SELECT ST_AsText(lonlat::geometry),velocity FROM points WHERE import_id=$1", [
          c.import.id
        ])
        |> Enum.map(fn [lonlat, v] -> %{"lonlat" => lonlat, "velocity" => v} end)

      assert actual == e["points"]

      notifications =
        rows("SELECT title,kind FROM notifications WHERE user_id=$1", [c.import.user_id])

      assert notifications == Enum.map(e["notifications"], fn n -> [n["title"], 2] end)
    end
  end
end
