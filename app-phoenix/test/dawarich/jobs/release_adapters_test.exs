defmodule Dawarich.Jobs.ReleaseAdaptersTest do
  use Dawarich.JobsCase
  alias Dawarich.Jobs.{Dispatch, Ownership, Registry}
  alias Dawarich.ReleaseOperations.{Achievements, ImportBackfill}

  @oban __MODULE__.Oban

  setup do
    start_oban(@oban)
    :ok
  end

  test "two release adapter keys default off and quarantine invalid versions before effects" do
    entries = Registry.entries()

    for {type, worker, payload} <- [
          {"release.achievements_backfill", Achievements, %{}},
          {"release.import_backfill", ImportBackfill,
           %{"import_id" => 54001, "ambient_zone" => "Europe/Berlin"}}
        ] do
      assert Registry.command(type) == {:ok, worker}
      entry = Enum.find(entries, &(&1.key == "command:" <> type))
      assert entry.claimable == false
      refute entry in Registry.claimable()
      assert entry.kind == :command
      assert Ownership.lock(ScratchRepo, entry.key) == :sidekiq
      job = worker.new(%{})
      assert Ecto.Changeset.get_field(job, :max_attempts) == 26
      assert Ecto.Changeset.get_field(job, :queue) == "maintenance"
      assert Ecto.Changeset.get_field(job, :priority) == 3
      assert {:ok, args} = worker.args_from_command(1, payload)
      assert args["version"] == 1
      assert worker.args_from_command(2, payload) == {:error, "unsupported_version"}

      assert worker.args_from_command(1, Map.put(payload, "extra", 1)) ==
               {:error, "invalid_payload"}

      assert worker.perform(%Oban.Job{args: %{"version" => 2}}) == {:cancel, :unsupported_version}

      bad = outbox!(command_type: type, command_version: 2, payload: payload)
      extra = outbox!(command_type: type, payload: Map.put(payload, "extra", 1))
      assert Dispatch.run(repo: ScratchRepo, oban: @oban) == %{quarantined: 2}

      assert rows("SELECT state,error_code FROM job_outbox WHERE event_id=$1", [
               Ecto.UUID.dump!(bad)
             ]) == [["quarantined", "unsupported_version"]]

      assert rows("SELECT state,error_code FROM job_outbox WHERE event_id=$1", [
               Ecto.UUID.dump!(extra)
             ]) == [["quarantined", "invalid_payload"]]

      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    end

    for payload <- [
          %{},
          %{"import_id" => 1},
          %{"ambient_zone" => "UTC"},
          %{"import_id" => 0, "ambient_zone" => "UTC"},
          %{"import_id" => -1, "ambient_zone" => "UTC"},
          %{"import_id" => "1", "ambient_zone" => "UTC"},
          %{"import_id" => 1, "ambient_zone" => nil},
          %{"import_id" => 1, "ambient_zone" => "../etc/passwd"},
          %{"import_id" => 1, "ambient_zone" => "Not/AZone"}
        ] do
      assert ImportBackfill.args_from_command(1, payload) == {:error, "invalid_payload"}
    end

    assert Achievements.args_from_command(1, %{"import_id" => 1}) == {:error, "invalid_payload"}
    sentinel = "command:achievements.check"
    Ownership.put!(ScratchRepo, sentinel, :oban, pinned: true)

    for key <- ~w(command:release.achievements_backfill command:release.import_backfill) do
      Ownership.put!(ScratchRepo, key, :sidekiq, pinned: true)
      Ownership.put!(ScratchRepo, key, :sidekiq, pinned: false)
    end

    assert rows("SELECT owner,pinned FROM phoenix.job_owners WHERE key=$1", [sentinel]) == [
             ["oban", true]
           ]

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.processed_commands") == [[0]]
  end

  test "explicit release bulk respects bulk and child owners through handback and publication failure" do
    alias Dawarich.Achievements.BulkCheck
    alias Dawarich.Jobs.Processed
    now = ~U[2026-10-04 12:00:00.000000Z]

    sequences =
      Map.new(
        ~w(users points countries regions),
        &{&1, rows("SELECT last_value,is_called FROM #{&1}_id_seq")}
      )

    owners =
      rows(
        "SELECT key,owner,pinned,updated_at,updated_by FROM phoenix.job_owners WHERE key=ANY($1)",
        [
          ~w(command:release.achievements_backfill command:achievements.bulk_check command:achievements.check cron:achievements_bulk_check_job)
        ]
      )

    on_exit(fn ->
      rows("DROP TRIGGER IF EXISTS a12rel_race_failure ON phoenix.rails_commands")
      rows("DROP FUNCTION IF EXISTS a12rel_race_failure()")
      rows("DELETE FROM points WHERE user_id BETWEEN 54501 AND 54903")
      rows("DELETE FROM achievement_progresses WHERE user_id BETWEEN 54501 AND 54903")
      rows("DELETE FROM users WHERE id BETWEEN 54501 AND 54903")
      rows("DELETE FROM regions")
      rows("DELETE FROM countries WHERE id=54001")

      rows("DELETE FROM phoenix.job_owners WHERE key=ANY($1)", [
        ~w(command:release.achievements_backfill command:achievements.bulk_check command:achievements.check cron:achievements_bulk_check_job)
      ])

      for row <- owners,
          do:
            rows(
              "INSERT INTO phoenix.job_owners(key,owner,pinned,updated_at,updated_by) VALUES($1,$2,$3,$4,$5)",
              row
            )

      for {table, [[value, called]]} <- sequences,
          do: rows("SELECT setval('#{table}_id_seq',$1,$2)", [value, called])
    end)

    rows(
      "INSERT INTO countries(id,name,iso_a2,iso_a3,created_at,updated_at) VALUES(54001,'synthetic','ZZ','ZZZ',now(),now())"
    )

    Ownership.put!(ScratchRepo, "command:release.achievements_backfill", :oban)
    Ownership.put!(ScratchRepo, "command:achievements.bulk_check", :oban)
    telemetry = {__MODULE__, make_ref()}
    parent = self()

    :ok =
      :telemetry.attach(
        telemetry,
        [:dawarich, :scratch_repo, :query],
        fn _, _, metadata, caller ->
          if self() == caller &&
               String.starts_with?(metadata.query, "SELECT key, owner FROM phoenix.job_owners") do
            [[first]] = rows("SELECT pg_backend_pid()")

            task =
              Task.async(fn ->
                ScratchRepo.checkout(fn ->
                  [[second]] = rows("SELECT pg_backend_pid()")
                  Ownership.put!(ScratchRepo, "command:release.achievements_backfill", :sidekiq)

                  {second,
                   Ownership.put!(ScratchRepo, "command:achievements.bulk_check", :sidekiq)}
                end)
              end)

            assert Dawarich.LockRace.settle(task, "SELECT key FROM phoenix.job_owners%") ==
                     :blocked

            send(parent, {:parent_released, first, task})
          end
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(telemetry) end)
    event = Ecto.UUID.generate()
    args = %{"version" => 1, "event_id" => event}
    assert Achievements.run(ScratchRepo, @oban, args, now: now) == :ok
    assert_receive {:parent_released, first, task}
    assert {second, :ok} = Task.await(task)
    assert first != second
    :telemetry.detach(telemetry)

    root = BulkCheck.job_id(BulkCheck.release_job_id(event))

    assert [[%{"event_id" => ^root}]] =
             rows(
               "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Achievements.BulkCheckWorker'"
             )

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert Processed.done?(ScratchRepo, event)
    assert Achievements.run(ScratchRepo, @oban, args, now: now) == :ok
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
    rows("DELETE FROM oban.oban_jobs")
    source_event = Ecto.UUID.generate()

    assert Achievements.run(ScratchRepo, @oban, Map.put(args, "event_id", source_event), now: now) ==
             :ok

    [["release_achievements_bulk_check", payload]] =
      rows("SELECT kind,payload FROM phoenix.rails_commands")

    assert payload["job_id"] == BulkCheck.release_job_id(source_event)
    assert payload["options"] == %{"notify" => false, "force" => true, "stale_only" => true}
    assert payload["run_at"] == DateTime.to_iso8601(now)
    assert Processed.done?(ScratchRepo, source_event)
    rows("DELETE FROM phoenix.rails_commands")

    for id <- 54_501..54_903 do
      rows(
        "INSERT INTO users(id,email,status,created_at,updated_at) VALUES($1,$2,1,now(),now())",
        [id, "a12rel-race-#{id}@example.invalid"]
      )

      rows(
        "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,1780300000,ST_SetSRID(ST_MakePoint(13,52),4326),now(),now())",
        [id]
      )
    end

    for {id, version} <- [{54_502, 3}, {54_903, 4}] do
      rows(
        "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES($1,'exploration',$2,now(),now())",
        [id, %{"calculation_version" => version}]
      )
    end

    ids = Enum.to_list(54_501..54_903) -- [54_502, 54_903]
    Ownership.put!(ScratchRepo, "cron:achievements_bulk_check_job", :sidekiq)

    for count <- [200, 201, 401] do
      rows("DELETE FROM oban.oban_jobs")
      rows("DELETE FROM phoenix.rails_commands")

      rows(
        "UPDATE users SET status=CASE WHEN id=ANY($1) THEN 1 ELSE 0 END WHERE id BETWEEN 54501 AND 54903",
        [Enum.take(ids, count) ++ [54_502, 54_903]]
      )

      root = Ecto.UUID.generate()
      bulk = Map.put(payload["options"], "event_id", root)
      Ownership.put!(ScratchRepo, "command:achievements.bulk_check", :sidekiq)
      Ownership.put!(ScratchRepo, "command:achievements.check", :oban)
      boundary = Enum.at(ids, 199)

      hook = fn id ->
        if id == boundary do
          task =
            Task.async(fn ->
              Ownership.put!(ScratchRepo, "command:achievements.check", :sidekiq)
            end)

          assert Dawarich.LockRace.wait_until(fn ->
                   Dawarich.LockRace.blocked("SELECT key FROM phoenix.job_owners%") > 0
                 end)

          send(parent, {:child_released, task})
        end
      end

      assert BulkCheck.run(ScratchRepo, @oban, bulk, now: now, hook: hook) == :ok
      assert_receive {:child_released, task}
      assert Task.await(task) == :ok

      native =
        rows("SELECT args,scheduled_at FROM oban.oban_jobs ORDER BY (args->>'user_id')::bigint")

      assert native ==
               Enum.map(Enum.take(ids, 200), fn id ->
                 [
                   %{
                     "user_id" => id,
                     "notify" => false,
                     "oldest_timestamp" => nil,
                     "event_id" => BulkCheck.child_id(root, id)
                   },
                   DateTime.to_naive(now)
                 ]
               end)

      reverse =
        rows("SELECT payload FROM phoenix.rails_commands ORDER BY (payload->>'user_id')::bigint")

      assert reverse ==
               Enum.with_index(Enum.take(ids, count))
               |> Enum.drop(200)
               |> Enum.map(fn {id, index} ->
                 [
                   %{
                     "user_id" => id,
                     "notify" => false,
                     "force" => true,
                     "event_id" => BulkCheck.child_id(root, id),
                     "run_at" => DateTime.to_iso8601(DateTime.add(now, div(index, 200) * 300))
                   }
                 ]
               end)

      assert BulkCheck.run(ScratchRepo, @oban, bulk, now: now) == :ok

      assert rows(
               "SELECT args,scheduled_at FROM oban.oban_jobs ORDER BY (args->>'user_id')::bigint"
             ) == native

      assert rows(
               "SELECT payload FROM phoenix.rails_commands ORDER BY (payload->>'user_id')::bigint"
             ) == reverse

      assert Processed.done?(ScratchRepo, root)
    end

    rows("DELETE FROM phoenix.rails_commands")

    rows(
      "CREATE FUNCTION a12rel_race_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'A12rel race publication'; END $$"
    )

    rows(
      "CREATE TRIGGER a12rel_race_failure BEFORE INSERT ON phoenix.rails_commands FOR EACH ROW EXECUTE FUNCTION a12rel_race_failure()"
    )

    failed = Ecto.UUID.generate()
    bulk = Map.put(payload["options"], "event_id", failed)
    assert_raise Postgrex.Error, fn -> BulkCheck.run(ScratchRepo, @oban, bulk, now: now) end
    refute Processed.done?(ScratchRepo, failed)
    refute Processed.done?(ScratchRepo, BulkCheck.receipt_id(failed, hd(ids)))
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    rows("DROP TRIGGER a12rel_race_failure ON phoenix.rails_commands")
    rows("DROP FUNCTION a12rel_race_failure()")
    assert BulkCheck.run(ScratchRepo, @oban, bulk, now: now) == :ok

    assert rows(
             "SELECT payload FROM phoenix.rails_commands ORDER BY (payload->>'user_id')::bigint"
           ) ==
             Enum.with_index(ids)
             |> Enum.map(fn {id, index} ->
               [
                 %{
                   "user_id" => id,
                   "notify" => false,
                   "force" => true,
                   "event_id" => BulkCheck.child_id(failed, id),
                   "run_at" => DateTime.to_iso8601(DateTime.add(now, div(index, 200) * 300))
                 }
               ]
             end)
  end
end
