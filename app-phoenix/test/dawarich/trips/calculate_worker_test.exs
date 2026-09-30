defmodule Dawarich.Trips.CalculateWorkerTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.Trips.CalculateWorker

  setup do
    [[user_id]] =
      rows(
        "INSERT INTO users (email, created_at, updated_at) VALUES ('t@example.test', now(), now()) RETURNING id"
      )

    [[trip_id]] =
      rows(
        """
        INSERT INTO trips (user_id, name, started_at, ended_at, last_recalculated_at, created_at, updated_at)
        VALUES ($1, 'Broken', '2026-06-01 08:00', '2026-06-01 10:00', now(), now(), now()) RETURNING id
        """,
        [user_id]
      )

    rows(
      "INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at) VALUES ($1, $2, NULL, now(), now()), ($1, $3, NULL, now(), now())",
      [user_id, 1_780_300_800, 1_780_300_860]
    )

    %{
      args: %{"event_id" => Ecto.UUID.generate(), "trip_id" => trip_id, "distance_unit" => "km"},
      trip_id: trip_id
    }
  end

  test "an early failed attempt reports nothing and keeps the cooldown", %{
    args: args,
    trip_id: id
  } do
    assert_raise FunctionClauseError, fn -> perform_job(CalculateWorker, args, attempt: 1) end
    assert rows("SELECT count(*) FROM phoenix.trip_events") == [[0]]

    assert [[%NaiveDateTime{}]] =
             rows("SELECT last_recalculated_at FROM trips WHERE id = $1", [id])
  end

  test "the last failed attempt clears the cooldown and reports the failure", %{
    args: args,
    trip_id: id
  } do
    assert_raise FunctionClauseError, fn -> perform_job(CalculateWorker, args, attempt: 3) end
    assert rows("SELECT kind, failed FROM phoenix.trip_events") == [["finished", true]]
    assert rows("SELECT last_recalculated_at FROM trips WHERE id = $1", [id]) == [[nil]]
  end

  test "decodes version 1 commands only" do
    assert CalculateWorker.args_from_command(1, %{"trip_id" => 3, "distance_unit" => "mi"}) ==
             {:ok, %{"trip_id" => 3, "distance_unit" => "mi"}}

    assert CalculateWorker.args_from_command(1, %{"trip_id" => "3"}) ==
             {:error, "invalid_payload"}

    assert CalculateWorker.args_from_command(2, %{}) == {:error, "unsupported_version"}
  end
end
