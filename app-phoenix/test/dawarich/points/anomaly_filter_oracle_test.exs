defmodule Dawarich.Points.AnomalyFilterOracleTest do
  use Dawarich.JobsCase
  import Dawarich.AnomalyCase

  @cases "test/fixtures/points/anomaly_filter_rails.json" |> File.read!() |> Jason.decode!()

  for {fixture, index} <- Enum.with_index(@cases) do
    @fixture fixture
    test "Rails persisted oracle #{index}: #{fixture["name"]}" do
      fixture = @fixture
      user = user!(fixture["settings"])

      fixture["before"]
      |> Enum.map(& &1["track_id"])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.each(fn track ->
        rows(
          "INSERT INTO tracks(id,user_id,start_at,end_at,original_path,created_at,updated_at) VALUES($1,$2,NOW(),NOW(),ST_GeomFromText('LINESTRING(13.405 52.52,13.406 52.52)',4326),NOW(),NOW())",
          [track, user]
        )
      end)

      identities =
        Map.new(fixture["before"], fn point ->
          id =
            point!(user, point["timestamp"], {point["longitude"], point["latitude"]},
              accuracy: point["accuracy"],
              tracker: point["tracker_id"],
              velocity: point["velocity"],
              vertical_accuracy: point["vertical_accuracy"],
              motion: point["motion_data"],
              raw: point["raw_data"],
              anomaly: point["anomaly"]
            )

          rows("UPDATE points SET track_id=$1 WHERE id=$2", [point["track_id"], id])
          {point["id"], id}
        end)

      assert filter(user, fixture["start"], fixture["end"], zone: fixture["zone"]) ==
               fixture["count"]

      for expected <- fixture["after"] do
        assert [[expected["anomaly"], expected["track_id"], expected["motion_data"]]] ==
                 rows("SELECT anomaly,track_id,motion_data FROM points WHERE id=$1", [
                   Map.fetch!(identities, expected["id"])
                 ])
      end
    end
  end
end
