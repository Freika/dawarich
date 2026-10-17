defmodule Dawarich.ReleaseOperations.BoundaryPointsTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db
  alias Dawarich.ReleaseOperations.BoundaryPoints
  @oban __MODULE__.Oban

  test "boundary batches retain provider labels and atomically preserve followups across replay" do
    start_oban(@oban)

    [[uid]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES('boundary@example.test',now(),now()) RETURNING id"
      )

    [[ru]] =
      rows(
        "INSERT INTO countries(name,iso_a2,iso_a3,geom,created_at,updated_at) VALUES('Russia','RU','RUS',ST_Multi(ST_MakeEnvelope(0,0,50,60,4326)),now(),now()) RETURNING id"
      )

    [[ua]] =
      rows(
        "INSERT INTO countries(name,iso_a2,iso_a3,geom,created_at,updated_at) VALUES('Ukraine','UA','UKR',ST_Multi(ST_MakeEnvelope(33,44.5,35,46,4326)),now(),now()) RETURNING id"
      )

    for {x, label, ts, cid} <- [
          {34.0, "Russia", 1000, ru},
          {34.1, "provider", 2000, ru},
          {36.5, "Russia", 3000, ru},
          {34.0, "", 4000, nil}
        ] do
      rows(
        "INSERT INTO points(user_id,timestamp,lonlat,country_id,country_name,country,created_at,updated_at) VALUES($1,$2,ST_SetSRID(ST_MakePoint($3,45),4326),$4,$5,$5,now(),now())",
        [uid, ts, x, cid, label]
      )
    end

    assert {:ok, BoundaryPoints, args} =
             Dawarich.ReleaseJobs.decode("DataMigrations::ReassignBoundaryPointsJob", [])

    job = %Oban.Job{args: args, attempt: 1, max_attempts: 26}

    on_exit(fn ->
      rows("DROP TRIGGER IF EXISTS s1160_boundary_fail ON oban.oban_jobs")
      rows("DROP FUNCTION IF EXISTS s1160_boundary_fail()")
    end)

    rows(
      "CREATE FUNCTION s1160_boundary_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.worker='Dawarich.Achievements.CheckWorker' THEN RAISE EXCEPTION 'synthetic publication failure'; END IF; RETURN NEW; END $$"
    )

    rows(
      "CREATE TRIGGER s1160_boundary_fail BEFORE INSERT ON oban.oban_jobs FOR EACH ROW EXECUTE FUNCTION s1160_boundary_fail()"
    )

    assert_raise Postgrex.Error, fn -> apply(BoundaryPoints, :run, [ScratchRepo, @oban, job]) end
    assert rows("SELECT count(*) FROM points WHERE country_id=$1", [ru]) == [[3]]
    assert rows("SELECT count(*) FROM phoenix.stats_geocoded_days") == [[0]]
    rows("DROP TRIGGER s1160_boundary_fail ON oban.oban_jobs")
    assert :ok = apply(BoundaryPoints, :run, [ScratchRepo, @oban, job])

    assert rows("SELECT country_id,country_name FROM points ORDER BY timestamp") == [
             [ua, "Ukraine"],
             [ua, "provider"],
             [ru, "Russia"],
             [nil, ""]
           ]

    assert rows("SELECT count(*) FROM phoenix.stats_geocoded_days") == [[1]]

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Achievements.CheckWorker'"
           ) == [[1]]

    assert :ok = apply(BoundaryPoints, :run, [ScratchRepo, @oban, job])

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Achievements.CheckWorker'"
           ) == [[1]]
  end
end
