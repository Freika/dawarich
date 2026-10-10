defmodule Dawarich.Achievements.BulkCheckTest do
  use Dawarich.JobsCase
  alias Dawarich.Achievements.{BulkCheck, BulkCheckWorker}
  alias Dawarich.Jobs.{Ownership, Processed}
  @oban __MODULE__.Oban
  @now ~U[2026-10-04 12:00:00Z]

  setup do
    start_oban(@oban)

    on_exit(fn ->
      rows(
        "DELETE FROM points WHERE user_id IN (SELECT id FROM users WHERE email LIKE 'bulk-achievements-%@example.test')"
      )
    end)

    Ownership.put!(ScratchRepo, "command:achievements.check", :oban)

    %{
      args: %{
        "notify" => false,
        "force" => false,
        "stale_only" => true,
        "event_id" => Ecto.UUID.generate()
      }
    }
  end

  test "shuffled source eligibility fixes each user offset across stale filtering and hand-back",
       %{args: args} do
    ids = Enum.to_list(59_001..59_402)

    for id <- Enum.reverse(ids) do
      rows(
        "INSERT INTO users(id,email,status,created_at,updated_at) VALUES($1,$2,1,now(),now())",
        [id, "bulk-achievements-order-#{id}@example.test"]
      )

      point(id)
    end

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES($1,'exploration',$2,now(),now())",
      [59_002, %{"calculation_version" => 3}]
    )

    assert BulkCheckWorker.run(ScratchRepo, @oban, args, now: @now) == :ok

    expected =
      Enum.with_index(ids -- [59_002]) |> Enum.map(fn {id, i} -> [id, div(i, 200) * 300] end)

    assert rows(
             "SELECT (args->>'user_id')::bigint,extract(epoch FROM scheduled_at-$1)::int FROM oban.oban_jobs ORDER BY (args->>'user_id')::bigint",
             [@now]
           ) == expected

    Ownership.put!(ScratchRepo, "command:achievements.check", :sidekiq)
    handed = Map.put(args, "event_id", Ecto.UUID.generate())
    assert BulkCheckWorker.run(ScratchRepo, @oban, handed, now: @now) == :ok

    assert rows(
             "SELECT (payload->>'user_id')::bigint,extract(epoch FROM (payload->>'run_at')::timestamptz-$1)::int FROM phoenix.rails_commands ORDER BY (payload->>'user_id')::bigint",
             [@now]
           ) == expected
  end

  test "bulk eligibility and stale filter stagger source batches with notify unchanged", %{
    args: args
  } do
    ids =
      rows(
        "INSERT INTO users(email,status,created_at,updated_at) SELECT 'bulk-achievements-'||n||'@example.test',CASE WHEN n%2=0 THEN 1 ELSE 2 END,now(),now() FROM generate_series(1,404) n RETURNING id"
      )
      |> List.flatten()

    rows(
      "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) SELECT id,1780300000,ST_SetSRID(ST_MakePoint(13,52),4326),now(),now() FROM users WHERE id=ANY($1)",
      [ids]
    )

    [current, stale, future, fresh | _] = ids

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES($1,'exploration',$2,now(),now()),($3,'exploration',$4,now(),now()),($5,'exploration',$6,now(),now()),($7,'other',$6,now(),now())",
      [
        current,
        %{"calculation_version" => 3},
        stale,
        %{"calculation_version" => 2},
        future,
        %{"calculation_version" => 4},
        fresh
      ]
    )

    inactive = user(0, "inactive")
    pending = user(3, "pending")
    deleted = user(1, "deleted")
    anomaly = user(1, "anomaly")
    incomplete = user(1, "incomplete")
    empty = user(1, "empty")
    for id <- [inactive, pending, deleted, anomaly, incomplete], do: point(id)
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [deleted])
    rows("UPDATE points SET anomaly=true WHERE user_id=$1", [anomaly])
    rows("UPDATE points SET lonlat=NULL WHERE user_id=$1", [incomplete])
    assert BulkCheckWorker.run(ScratchRepo, @oban, args, now: @now) == :ok

    jobs =
      rows(
        "SELECT (args->>'user_id')::bigint,args->'notify',args->'oldest_timestamp',extract(epoch FROM scheduled_at-$1)::int FROM oban.oban_jobs ORDER BY id",
        [@now]
      )

    expected = Enum.reject(ids, &(&1 in [current, future]))
    assert Enum.map(jobs, &hd/1) == expected

    assert Enum.map(jobs, fn [_id, notify, oldest, delay] -> [notify, oldest, delay] end) ==
             Enum.with_index(expected)
             |> Enum.map(fn {_id, index} -> [false, nil, div(index, 200) * 300] end)

    refute Enum.any?(jobs, &(hd(&1) in [inactive, pending, deleted, anomaly, incomplete, empty]))
    assert BulkCheckWorker.run(ScratchRepo, @oban, args, now: @now) == :ok
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[402]]
    assert BulkCheckWorker.__opts__()[:max_attempts] == 26
  end

  @tag a12f3b_case: "E05Ab"
  test "force stays inert and each check follows its current leaf owner", %{args: args} do
    id = user(1, "force")
    point(id)
    payload = Map.put(args, "force", true)

    assert BulkCheckWorker.args_from_command(1, Map.delete(payload, "event_id")) ==
             {:ok, Map.delete(payload, "event_id")}

    assert BulkCheckWorker.args_from_command(
             1,
             Map.put(Map.delete(payload, "event_id"), "extra", 1)
           ) == {:error, "invalid_payload"}

    assert BulkCheckWorker.args_from_command(2, Map.delete(payload, "event_id")) ==
             {:error, "unsupported_version"}

    assert_raise Postgrex.Error, fn ->
      BulkCheckWorker.run(ScratchRepo, @oban, payload,
        now: @now,
        hook: fn _ -> rows("SELECT 1/0") end
      )
    end

    refute Processed.done?(ScratchRepo, BulkCheck.receipt_id(payload["event_id"], id))
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert BulkCheckWorker.run(ScratchRepo, @oban, payload, now: @now) == :ok
    [[native]] = rows("SELECT args FROM oban.oban_jobs")

    assert native == %{
             "user_id" => id,
             "notify" => false,
             "oldest_timestamp" => nil,
             "event_id" => BulkCheck.child_id(payload["event_id"], id)
           }

    Ownership.put!(ScratchRepo, "command:achievements.check", :sidekiq)
    reverse = Map.put(payload, "event_id", Ecto.UUID.generate())
    assert BulkCheckWorker.run(ScratchRepo, @oban, reverse, now: @now) == :ok
    assert BulkCheckWorker.run(ScratchRepo, @oban, reverse, now: @now) == :ok

    assert rows("SELECT kind,payload FROM phoenix.rails_commands") == [
             [
               "achievements.bulk_check_leaf",
               %{
                 "user_id" => id,
                 "notify" => false,
                 "force" => true,
                 "event_id" => BulkCheck.child_id(reverse["event_id"], id),
                 "run_at" => "2026-10-04T12:00:00Z"
               }
             ]
           ]

    root = BulkCheck.cron_id(1_791_115_200)

    assert BulkCheckWorker.run_cron(ScratchRepo, @oban, 1_791_115_200, now: @now) ==
             {:cancel, :not_owner}

    refute Processed.done?(ScratchRepo, BulkCheck.receipt_id(root, id))
    Ownership.put!(ScratchRepo, BulkCheckWorker.key(), :oban)
    assert BulkCheckWorker.run_cron(ScratchRepo, @oban, 1_791_115_200, now: @now) == :ok
    assert BulkCheckWorker.run_cron(ScratchRepo, @oban, 1_791_115_200, now: @now) == :ok
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[2]]
    Ownership.put!(ScratchRepo, BulkCheckWorker.key(), :sidekiq)

    assert BulkCheckWorker.run_cron(ScratchRepo, @oban, 1_791_115_200, now: @now) ==
             {:cancel, :not_owner}
  end

  defp user(status, suffix) do
    [[id]] =
      rows(
        "INSERT INTO users(email,status,created_at,updated_at) VALUES($1,$2,now(),now()) RETURNING id",
        ["bulk-achievements-#{suffix}@example.test", status]
      )

    id
  end

  defp point(id),
    do:
      rows(
        "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,1780300000,ST_SetSRID(ST_MakePoint(13,52),4326),now(),now())",
        [id]
      )
end
