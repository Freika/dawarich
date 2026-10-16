defmodule Dawarich.Achievements.Sync1160GeographyTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.Achievements.{Checker, Dwell, Registry}

  setup do
    rows(
      "CREATE TABLE IF NOT EXISTS disputed_areas (id bigserial PRIMARY KEY, name varchar NOT NULL, geom geometry(Geometry,4326) NOT NULL, created_at timestamp(6) NOT NULL, updated_at timestamp(6) NOT NULL)"
    )

    rows("DELETE FROM disputed_areas")
    on_exit(fn -> rows("DELETE FROM disputed_areas") end)

    [[uid]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES('sync1160@example.test','{\"min_minutes_spent_in_city\":10}',now(),now()) RETURNING id"
      )

    [[cid]] =
      rows(
        "INSERT INTO countries(name,iso_a2,iso_a3,geom,created_at,updated_at) VALUES('Germany','DE','DEU',ST_Multi(ST_MakeEnvelope(0,0,10,10,4326)),now(),now()) RETURNING id"
      )

    rows(
      "INSERT INTO regions(code,geom,created_at,updated_at) VALUES('DE-BE',ST_Multi(ST_MakeEnvelope(0,0,10,10,4326)),now(),now())"
    )

    %{uid: uid, cid: cid}
  end

  test "historical geography dates repair check dates and preserve earlier dates and deleted history",
       %{uid: uid, cid: cid} do
    points(uid, cid, [{1000, 1.001}, {1600, 1.001}, {2200, 1.001}])
    assert :ok = Checker.run(ScratchRepo, uid, false, nil)
    [[state]] = rows("SELECT state FROM achievement_progresses WHERE user_id=$1", [uid])
    assert state["earned"] == %{"DE" => "1970-01-01T00:16:40Z", "DE-BE" => "1970-01-01T00:16:40Z"}

    rows(
      "UPDATE achievement_progresses SET state=jsonb_set(jsonb_set(state,'{calculation_version}','3'),'{earned}','{\"DE\":\"2026-01-01T00:00:00Z\",\"DE-BE\":\"1970-01-01T00:00:01Z\",\"ZZ\":\"2000-01-01T00:00:00Z\"}') WHERE user_id=$1",
      [uid]
    )

    Checker.run(ScratchRepo, uid, false, nil)
    [[state]] = rows("SELECT state FROM achievement_progresses WHERE user_id=$1", [uid])
    assert state["earned"]["DE"] == "1970-01-01T00:16:40Z"
    assert state["earned"]["DE-BE"] == "1970-01-01T00:00:01Z"
    assert state["earned"]["ZZ"] == "2000-01-01T00:00:00Z"
    assert state["calculation_version"] == 5
  end

  test "exact disputed masks break dwell pairs without discarding nearby points in the same cell",
       %{uid: uid, cid: cid} do
    rows(
      "INSERT INTO disputed_areas(name,geom,created_at,updated_at) VALUES('synthetic',ST_MakeEnvelope(1.002,1.002,1.004,1.004,4326),now(),now())"
    )

    points(uid, cid, [{1000, 1.001}, {1600, 1.003}, {2200, 1.001}, {2800, 1.001}])
    assert Dwell.countries(ScratchRepo, uid, 0, 3000) == %{"DE" => 600}
    assert Dwell.grid(ScratchRepo, "regions", uid, 0, 3000) == %{"DE-BE" => 600}
    rows("UPDATE points SET country_id=NULL WHERE user_id=$1", [uid])
    assert Dwell.countries(ScratchRepo, uid, 0, 3000) == %{"DE" => 600}
  end

  test "first seen includes untagged history with tagged incremental coverage and excludes anomalies",
       %{uid: uid, cid: cid} do
    points(uid, nil, [{500, 1.001}])
    points(uid, cid, for(i <- 0..10, do: {1000 + i * 60, 1.001}))
    points(uid, cid, [{1, 1.001}])
    rows("UPDATE points SET anomaly=true WHERE user_id=$1 AND timestamp=1", [uid])
    assert Dwell.first_seen(ScratchRepo, uid, 1000, 2000)["DE"] == 500
  end

  test "disputed subdivisions never count toward registry targets" do
    refute "UA-43" in Registry.find("country_ua").region_codes
    refute "IN-JK" in Registry.find("country_in").region_codes
    assert Registry.find("country_ua").target == 25
  end

  defp points(uid, cid, positions) do
    for {ts, x} <- positions do
      rows(
        "INSERT INTO points(user_id,timestamp,lonlat,country_id,anomaly,created_at,updated_at) VALUES($1,$2,ST_SetSRID(ST_MakePoint($3,$3),4326),$4,false,now(),now())",
        [uid, ts, x, cid]
      )
    end
  end
end
