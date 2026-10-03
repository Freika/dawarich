defmodule Dawarich.Points.AnomalyFilterEffectsTest do
  use Dawarich.JobsCase
  import Dawarich.AnomalyCase
  alias Dawarich.Points.AnomalyFilter
  alias Dawarich.Points.AnomalyFilter.RecalculateWorker
  alias Dawarich.Jobs.{Ownership, Dispatch, Registry}

  @at DateTime.to_unix(~U[2023-12-31 23:59:00Z])

  setup do
    start_supervised!(hd(Dawarich.Redis.child_specs()))
    :ok
  end

  test "default dependents preserve captured local months, track uniqueness and oldest achievement deferred" do
    user = user!()
    track = track!(user)
    first = point!(user, @at, {13.405, 52.52}, accuracy: 20_000)
    second = point!(user, @at + 120, {13.406, 52.52}, accuracy: 30_000)
    rows("UPDATE points SET track_id=$1 WHERE id=ANY($2::bigint[])", [track, [first, second]])
    assert AnomalyFilter.call(ScratchRepo, user, @at, @at + 120, zone: "Europe/Berlin") == 2

    assert [[nil], [nil]] ==
             rows("SELECT track_id FROM points WHERE id=ANY($1::bigint[]) ORDER BY id", [
               [first, second]
             ])

    assert [[%{"user_id" => user, "timestamps" => [@at, @at + 120]}]] ==
             rows("SELECT payload FROM phoenix.rails_commands WHERE kind='points.tile_epoch'")

    assert [[%{"user_id" => user, "track_id" => track, "job_queue" => nil}]] ==
             rows(
               "SELECT payload FROM phoenix.rails_commands WHERE kind='points.anomaly_recalculate'"
             )

    assert [
             [
               %{
                 "user_id" => user,
                 "year" => 2024,
                 "month" => 1,
                 "job_queue" => nil,
                 "time_zone" => "Europe/Berlin"
               }
             ]
           ] ==
             rows("SELECT payload FROM phoenix.rails_commands WHERE kind='points.anomaly_stats'")

    assert {:ok, [member]} =
             Dawarich.Redis.command([
               "ZRANGE",
               "achievements_check:user:#{user}:oldest",
               "0",
               "-1"
             ])

    assert member =~ "#{@at}:"
    assert {:ok, ttl} = Dawarich.Redis.command(["TTL", "achievements_check:user:#{user}:oldest"])
    assert ttl > 259_190 and ttl <= 259_200
  end

  test "backfill opt-out retains flag detach and exact tile years but no rebuild" do
    user = user!()
    point!(user, @at, {0, 0})
    assert AnomalyFilter.call(ScratchRepo, user, @at, @at, invalidate_dependents: false) == 1
    assert [["points.tile_epoch"]] == rows("SELECT kind FROM phoenix.rails_commands")
    assert [] == rows("SELECT command_type FROM job_outbox")
  end

  test "sentinel lookback invalidates previous year and its local month, not only caller window" do
    user = user!()
    point!(user, @at, {13.405, 52.52}, accuracy: 1500, velocity: "-1", vertical_accuracy: -1)
    point!(user, @at + 120, {13.405, 52.52}, accuracy: 10)
    assert AnomalyFilter.call(ScratchRepo, user, @at + 120, @at + 120, zone: "UTC") == 1

    assert [[%{"user_id" => user, "timestamps" => [@at]}]] ==
             rows("SELECT payload FROM phoenix.rails_commands WHERE kind='points.tile_epoch'")

    assert [[12]] ==
             rows(
               "SELECT (payload->>'month')::int FROM phoenix.rails_commands WHERE kind='points.anomaly_stats'"
             )
  end

  test "native-owned tracks enter real outbox and dispatch with override queue without new owner lane" do
    user = user!()
    track = track!(user)
    id = point!(user, @at, {0, 0})
    rows("UPDATE points SET track_id=$1 WHERE id=$2", [track, id])
    Ownership.put!(ScratchRepo, "command:tracks.recalculate", :oban)
    assert AnomalyFilter.call(ScratchRepo, user, @at, @at, job_queue: :low_priority) == 1

    assert [
             [
               "points.anomaly_recalculate",
               1,
               %{"track_id" => track, "job_queue" => "low_priority", "user_id" => user}
             ]
           ] == rows("SELECT command_type,command_version,payload FROM job_outbox")

    start_oban(:anomaly_effects)
    [[scheduled]] = rows("SELECT scheduled_at FROM job_outbox")
    assert {:ok, RecalculateWorker} = Registry.command("points.anomaly_recalculate")

    assert %{dispatched: 1} ==
             Dispatch.run(
               repo: ScratchRepo,
               oban: :anomaly_effects,
               now: DateTime.add(scheduled, 1)
             )

    assert [["low_priority"]] == rows("SELECT queue FROM oban.oban_jobs")
    assert [["command:tracks.recalculate"]] == rows("SELECT key FROM phoenix.job_owners")
  end

  test "native wrapper handback creates durable Rails recalculation with queue preserved" do
    user = user!()
    track = track!(user)

    args = %{
      "track_id" => track,
      "user_id" => user,
      "job_queue" => "low_priority",
      "event_id" => Ecto.UUID.generate()
    }

    assert :ok == RecalculateWorker.run(ScratchRepo, args)

    assert [[%{"user_id" => user, "track_id" => track, "job_queue" => "low_priority"}]] ==
             rows(
               "SELECT payload FROM phoenix.rails_commands WHERE kind='points.anomaly_recalculate'"
             )
  end

  test "native wrapper invokes real recalculator and removes track husk with no remaining points" do
    user = user!()
    track = track!(user)
    Ownership.put!(ScratchRepo, "command:tracks.recalculate", :oban)

    assert :ok ==
             RecalculateWorker.run(ScratchRepo, %{
               "track_id" => track,
               "user_id" => user,
               "job_queue" => nil
             })

    assert [] == rows("SELECT id FROM tracks WHERE id=$1", [track])
    assert [["tracks_changed"]] == rows("SELECT kind FROM phoenix.rails_commands")
  end

  test "queue-aware decoder rejects unknown fields, types and bad versions" do
    payload = %{"track_id" => 1, "user_id" => 2, "job_queue" => nil}
    assert {:ok, ^payload} = RecalculateWorker.args_from_command(1, payload)
    assert {:error, "unsupported_version"} = RecalculateWorker.args_from_command(2, payload)

    for bad <- [
          Map.put(payload, "job_queue", 3),
          Map.put(payload, "extra", true),
          Map.put(payload, "track_id", "1"),
          Map.put(payload, "job_queue", "")
        ],
        do: assert({:error, "invalid_payload"} = RecalculateWorker.args_from_command(1, bad))
  end

  test "dependent-stage cancellation retains flags and tile effect but forbids later effects" do
    user = user!()
    point!(user, @at, {0, 0})
    Process.put(:anomaly_stage, 0)

    fence = fn fun ->
      n = Process.get(:anomaly_stage)
      Process.put(:anomaly_stage, n + 1)
      if n == 2, do: raise(Dawarich.Imports.LeaseLost)
      fun.()
    end

    assert_raise Dawarich.Imports.LeaseLost, fn ->
      AnomalyFilter.call(ScratchRepo, user, @at, @at, fence: fence)
    end

    assert length(flagged(user)) == 1
    assert [["points.tile_epoch"]] == rows("SELECT kind FROM phoenix.rails_commands")
  end

  defp track!(user) do
    [[id]] =
      rows(
        "INSERT INTO tracks(user_id,start_at,end_at,original_path,created_at,updated_at) VALUES($1,NOW(),NOW(),ST_GeomFromText('LINESTRING(13.405 52.52,13.406 52.52)',4326),NOW(),NOW()) RETURNING id",
        [user]
      )

    id
  end
end
