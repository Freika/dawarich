defmodule Dawarich.Trips.CalculationTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.Trips.Calculation

  defmodule LockTimeoutRepo do
    def transaction(fun) do
      ScratchRepo.transaction(fn ->
        ScratchRepo.query!("SET LOCAL lock_timeout = '50ms'", [], log: false)
        fun.()
      end)
    end

    def query!(sql, params, opts), do: ScratchRepo.query!(sql, params, opts)
  end

  @fixture Path.expand("../../fixtures/trips/calculation.json", __DIR__)

  defp load! do
    fixture = @fixture |> File.read!() |> Jason.decode!()

    rows(
      "INSERT INTO users (id, email, settings, created_at, updated_at) SELECT id, email, settings, created_at, updated_at FROM json_populate_record(NULL::users, $1)",
      [fixture["user"]]
    )

    for source <- fixture["point_sources"],
        do:
          rows(
            "INSERT INTO point_sources SELECT * FROM json_populate_record(NULL::point_sources, $1)",
            [source]
          )

    for point <- fixture["points"],
        do:
          rows("INSERT INTO points SELECT * FROM json_populate_record(NULL::points, $1)", [point])

    rows(
      "INSERT INTO trips (id, user_id, name, started_at, ended_at, created_at, updated_at) SELECT id, user_id, name, started_at, ended_at, created_at, updated_at FROM json_populate_record(NULL::trips, $1)",
      [fixture["trip"]]
    )

    fixture
  end

  defp trip_row(id),
    do:
      rows(
        "SELECT encode(ST_AsEWKB(path), 'hex'), distance, visited_countries, updated_at, last_recalculated_at FROM trips WHERE id = $1",
        [id]
      )

  defp events, do: rows("SELECT kind, distance_unit, failed FROM phoenix.trip_events ORDER BY id")

  test "computes the path, distance and countries Rails computes for the same rows, and reports each step" do
    fixture = load!()
    id = fixture["trip"]["id"]

    assert Calculation.run(ScratchRepo, id, "mi") == :ok

    expected = fixture["expected"]
    assert [[path, distance, countries, _updated, nil]] = trip_row(id)
    assert path == expected["path_ewkb"]
    assert distance == expected["distance"]
    assert countries == expected["visited_countries"]

    assert events() == [
             ["path", "mi", false],
             ["distance", "mi", false],
             ["countries", "mi", false],
             ["finished", "mi", false]
           ]
  end

  test "an unchanged recalculation keeps updated_at, clears the cooldown and reports again without a refresh" do
    fixture = load!()
    id = fixture["trip"]["id"]
    :ok = Calculation.run(ScratchRepo, id, "km")
    [[_, _, _, updated_at, _]] = trip_row(id)
    rows("UPDATE trips SET last_recalculated_at = now() WHERE id = $1", [id])
    rows("DELETE FROM phoenix.trip_events")

    assert Calculation.run(ScratchRepo, id, "km") == :ok
    assert [[_, _, _, ^updated_at, nil]] = trip_row(id)

    assert events() == [
             ["distance", "km", false],
             ["countries", "km", false],
             ["finished", "km", false]
           ]
  end

  test "a deleted trip is a no-op" do
    assert Calculation.run(ScratchRepo, 987_654, "km") == :missing
    assert events() == []
  end

  test "a competing row lock delays a calculation step until the newer range supersedes it" do
    fixture = load!()
    id = fixture["trip"]["id"]
    parent = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!("SET LOCAL lock_timeout = '50ms'", [], log: false)
          ScratchRepo.query!("SELECT id FROM trips WHERE id = $1 FOR UPDATE", [id], log: false)
          send(parent, :holding_trip_lock)

          receive do
            :update_and_release ->
              ScratchRepo.query!(
                "UPDATE trips SET started_at = started_at - interval '1 day', ended_at = ended_at + interval '1 day' WHERE id = $1",
                [id],
                log: false
              )
          end
        end)
      end)

    on_exit(fn ->
      if Process.alive?(holder.pid), do: send(holder.pid, :update_and_release)
    end)

    assert_receive :holding_trip_lock

    calculating =
      Task.async(fn ->
        Calculation.run(LockTimeoutRepo, id, "km", fn
          :path_computed -> send(parent, :path_computed)
        end)
      end)

    assert_receive :path_computed
    assert Task.yield(calculating, 25) == nil

    send(holder.pid, :update_and_release)
    assert {:ok, %{num_rows: 1}} = Task.await(holder)

    assert Task.await(calculating) == :superseded
    assert [[nil, nil, _, _, _]] = trip_row(id)
    assert events() == []
  end

  test "a trip whose range changes before its calculation step is left to the newer command" do
    fixture = load!()
    id = fixture["trip"]["id"]

    hook = fn :path_computed ->
      rows("UPDATE trips SET ended_at = ended_at + interval '1 day' WHERE id = $1", [id])
    end

    assert Calculation.run(ScratchRepo, id, "km", hook) == :superseded
    assert [[nil, nil, _, _, _]] = trip_row(id)
    assert events() == []
  end

  test "fewer than two points leave no path, zero distance and no countries" do
    fixture = load!()
    id = fixture["trip"]["id"]
    rows("DELETE FROM points")

    assert Calculation.run(ScratchRepo, id, "km") == :ok
    assert [[nil, 0, [], _, _]] = trip_row(id)

    assert events() == [
             ["distance", "km", false],
             ["countries", "km", false],
             ["finished", "km", false]
           ]
  end
end
