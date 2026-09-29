defmodule Dawarich.Imports.UpdatePointsCountWorkerTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.Imports.UpdatePointsCountWorker

  setup do
    rows("TRUNCATE public.imports, public.points RESTART IDENTITY CASCADE")

    [[user_id]] =
      rows(
        "INSERT INTO users (email, created_at, updated_at) VALUES ('w4@example.test', now(), now()) RETURNING id"
      )

    [[import_id]] =
      rows(
        "INSERT INTO imports (name, user_id, processed, created_at, updated_at) VALUES ('a.gpx', $1, 0, now(), now() - interval '1 day') RETURNING id",
        [user_id]
      )

    rows(
      "INSERT INTO points (user_id, import_id, timestamp, lonlat, created_at, updated_at) SELECT $1, $2, 1700000000 + g, ST_SetSRID(ST_MakePoint(13.4, 52.5 + g * 0.001), 4326)::geography, now(), now() FROM generate_series(1, 3) g",
      [user_id, import_id]
    )

    %{import_id: import_id}
  end

  defp run(import_id),
    do:
      perform_job(UpdatePointsCountWorker, %{
        "event_id" => Ecto.UUID.generate(),
        "import_id" => import_id
      })

  test "recounts processed and touches updated_at", %{import_id: id} do
    assert run(id) == :ok

    assert [[3, true]] =
             rows(
               "SELECT processed, updated_at > now() - interval '1 minute' FROM imports WHERE id = $1",
               [id]
             )
  end

  test "leaves the row untouched when the count is already right", %{import_id: id} do
    rows("UPDATE imports SET processed = 3 WHERE id = $1", [id])
    assert run(id) == :ok

    assert [[3, false]] =
             rows(
               "SELECT processed, updated_at > now() - interval '1 minute' FROM imports WHERE id = $1",
               [id]
             )
  end

  test "counts only this import's points", %{import_id: id} do
    [[user_id]] = rows("SELECT user_id FROM imports WHERE id = $1", [id])

    [[other]] =
      rows(
        "INSERT INTO imports (name, user_id, created_at, updated_at) VALUES ('b.gpx', $1, now(), now()) RETURNING id",
        [user_id]
      )

    rows(
      "INSERT INTO points (user_id, import_id, timestamp, lonlat, created_at, updated_at) VALUES ($1, $2, 1800000000, ST_SetSRID(ST_MakePoint(2.3, 48.8), 4326)::geography, now(), now())",
      [user_id, other]
    )

    assert run(id) == :ok
    assert [[3]] = rows("SELECT processed FROM imports WHERE id = $1", [id])
  end

  test "a missing import is :ok" do
    assert run(987_654) == :ok
  end

  test "decodes only the exact v1 payload" do
    assert UpdatePointsCountWorker.args_from_command(1, %{"import_id" => 7}) ==
             {:ok, %{"import_id" => 7}}

    assert UpdatePointsCountWorker.args_from_command(1, %{"import_id" => 7, "user_id" => 1}) ==
             {:error, "invalid_payload"}

    assert UpdatePointsCountWorker.args_from_command(1, %{"import_id" => "7"}) ==
             {:error, "invalid_payload"}

    assert UpdatePointsCountWorker.args_from_command(2, %{"import_id" => 7}) ==
             {:error, "unsupported_version"}
  end
end
