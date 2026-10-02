defmodule Dawarich.Imports.DestroyWorkerTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.{Destroy, DestroyWorker, DestroyLease, LeaseLost}
  alias Dawarich.Jobs.{Ownership, Processed, Dispatch}

  setup do
    previous_repo = Application.fetch_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

    on_exit(fn ->
      case previous_repo do
        {:ok, repo} -> Application.put_env(:dawarich, :jobs_repo, repo)
        :error -> Application.delete_env(:dawarich, :jobs_repo)
      end
    end)

    [[user], [other]] =
      rows(
        "INSERT INTO users(email,points_count,created_at,updated_at) VALUES('delete-worker@example.test',3,now(),now()),('other-delete-worker@example.test',0,now(),now()) RETURNING id"
      )

    [[id]] =
      rows(
        "INSERT INTO imports(user_id,name,source,status,created_at,updated_at) VALUES($1,'delete.csv',10,2,now(),now()) RETURNING id",
        [user]
      )

    Ownership.put!(ScratchRepo, "command:imports.destroy", :oban)
    event = Ecto.UUID.generate()
    args = %{"import_id" => id, "user_id" => user, "event_id" => event}

    [[job_id]] =
      rows(
        "INSERT INTO oban.oban_jobs(state,queue,worker,args,attempt,max_attempts,attempted_at) VALUES('executing','imports','Dawarich.Imports.DestroyWorker',$1,1,3,now()) RETURNING id",
        [args]
      )

    %{
      id: id,
      user: user,
      other: other,
      event: event,
      job: %Oban.Job{id: job_id, attempt: 1, args: args}
    }
  end

  test "strict decoder and real Oban dispatch preserve the exact canonical pair", c do
    assert {:ok, %{"import_id" => c.id, "user_id" => c.user}} ==
             DestroyWorker.args_from_command(1, %{"import_id" => c.id, "user_id" => c.user})

    assert {:error, "invalid_payload"} =
             DestroyWorker.args_from_command(1, %{
               "import_id" => c.id,
               "user_id" => c.user,
               "extra" => true
             })

    assert {:error, "unsupported_version"} = DestroyWorker.args_from_command(2, %{})
    rows("UPDATE oban.oban_jobs SET state='cancelled' WHERE id=$1", [c.job.id])

    assert {:ok, :queued} =
             Destroy.enqueue(ScratchRepo, c.user, c.id, %{zone: "UTC", locale: "en"})

    oban = Dawarich.DestroyOban
    start_oban(oban)
    [[scheduled]] = rows("SELECT scheduled_at FROM job_outbox")

    assert %{dispatched: 1} =
             Dispatch.run(repo: ScratchRepo, oban: oban, now: DateTime.add(scheduled, 1))

    assert [["imports", "Dawarich.Imports.DestroyWorker"]] =
             rows("SELECT queue,worker FROM oban.oban_jobs WHERE id<>$1", [c.job.id])
  end

  test "normal deletion removes all points and publishes durable terminal followups", c do
    points!(c)
    assert :ok = DestroyWorker.perform(c.job)
    assert [] = rows("SELECT id FROM imports WHERE id=$1", [c.id])
    assert [] = rows("SELECT id FROM points WHERE import_id=$1", [c.id])
    assert [[0]] = rows("SELECT points_count FROM users WHERE id=$1", [c.user])

    assert [["removed"]] =
             rows("SELECT phase FROM phoenix.import_destroy_runs WHERE import_id=$1", [c.id])

    assert Processed.done?(ScratchRepo, c.event)
    assert :ok = DestroyWorker.perform(c.job)

    assert [[1]] =
             rows(
               "SELECT count(*) FROM phoenix.rails_commands WHERE kind='imports.destroy_stats'"
             )
  end

  for {name, sql, field} <- [
        {"cancelled", "UPDATE oban.oban_jobs SET state='cancelled' WHERE id=$1", :job},
        {"attempt replaced", "UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", :job},
        {"different worker", "UPDATE oban.oban_jobs SET worker='OtherWorker' WHERE id=$1", :job},
        {"envelope replaced",
         "UPDATE oban.oban_jobs SET args=jsonb_set(args,'{user_id}','0') WHERE id=$1", :job},
        {"deleted user", "UPDATE users SET deleted_at=now() WHERE id=$1", :user},
        {"import reassigned", "UPDATE imports SET user_id=0 WHERE id=$1", :id}
      ] do
    test "#{name} cannot perform an effect or consume a stale attempt", c do
      value = if unquote(field) == :job, do: c.job.id, else: Map.fetch!(c, unquote(field))
      rows(unquote(sql), [value])

      assert {:skip, _} =
               DestroyLease.with_import(ScratchRepo, c.job, fn _ ->
                 flunk("stale lease acquired")
               end)

      refute Processed.done?(ScratchRepo, c.event)
    end
  end

  test "ownership loss after a committed batch stops without a false failed status", c do
    assert {:ok, :stopped} =
             DestroyLease.with_import(ScratchRepo, c.job, fn lease ->
               DestroyLease.effect!(lease, fn ->
                 rows("UPDATE imports SET processed=7 WHERE id=$1", [c.id])
               end)

               Ownership.put!(ScratchRepo, "command:imports.destroy", :sidekiq)

               assert_raise LeaseLost, fn ->
                 DestroyLease.effect!(lease, fn ->
                   rows("UPDATE imports SET status=3 WHERE id=$1", [c.id])
                 end)
               end

               :stopped
             end)

    assert [[4, 7]] = rows("SELECT status,processed FROM imports WHERE id=$1", [c.id])
  end

  test "a Rails-held import lease excludes deletion until it ends", c do
    foreign_lease!("import:#{c.id}")

    assert {:skip, :busy} =
             DestroyLease.with_import(ScratchRepo, c.job, fn _ -> flunk("lease overlapped") end)

    end_foreign_lease!("import:#{c.id}")
    assert {:ok, :ran} = DestroyLease.with_import(ScratchRepo, c.job, fn _ -> :ran end)
    assert [] = rows("SELECT name FROM phoenix.leases")
  end

  test "extracted visits and tracks release other points and remove dependent records", c do
    [[place]] =
      rows(
        "INSERT INTO places(user_id,import_id,name,latitude,longitude,lonlat,created_at,updated_at) VALUES($1,$2,'Extracted',50,10,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now()) RETURNING id",
        [c.user, c.id]
      )

    [[kept]] =
      rows(
        "INSERT INTO places(user_id,import_id,name,latitude,longitude,lonlat,created_at,updated_at) VALUES($1,$2,'Retained',51,11,ST_SetSRID(ST_MakePoint(11,51),4326)::geography,now(),now()) RETURNING id",
        [c.user, c.id]
      )

    [[visit]] =
      rows(
        "INSERT INTO visits(user_id,import_id,place_id,name,started_at,ended_at,duration,created_at,updated_at) VALUES($1,$2,$3,'Extracted',now()-interval '1 hour',now(),3600,now(),now()) RETURNING id",
        [c.user, c.id, place]
      )

    rows(
      "INSERT INTO visits(user_id,place_id,name,started_at,ended_at,duration,created_at,updated_at) VALUES($1,$2,'Detected',now()-interval '2 hours',now(),7200,now(),now())",
      [c.user, kept]
    )

    track = track!(c, c.id, 100)

    rows(
      "INSERT INTO track_segments(track_id,start_index,end_index,created_at,updated_at) VALUES($1,0,1,now(),now())",
      [track]
    )

    rows(
      "INSERT INTO notes(user_id,attachable_type,attachable_id,body,noted_at,created_at,updated_at) VALUES($1,'Visit',$2,'visit',now(),now(),now()),($1,'Place',$3,'place',now(),now(),now())",
      [c.user, visit, place]
    )

    rows(
      "INSERT INTO points(user_id,visit_id,track_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,$3,123,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now())",
      [c.user, visit, track]
    )

    assert :ok = DestroyWorker.perform(c.job)
    assert [] = rows("SELECT id FROM visits WHERE id=$1", [visit])
    assert [] = rows("SELECT id FROM places WHERE id=$1", [place])
    assert [[nil]] = rows("SELECT import_id FROM places WHERE id=$1", [kept])
    assert [[nil, nil]] = rows("SELECT visit_id,track_id FROM points WHERE user_id=$1", [c.user])
    assert [] = rows("SELECT id FROM notes WHERE user_id=$1", [c.user])
    assert [] = rows("SELECT id FROM track_segments WHERE track_id=$1", [track])

    assert [["visit_months_changed"]] =
             rows("SELECT kind FROM phoenix.rails_commands WHERE kind='visit_months_changed'")

    assert [["tracks_changed"]] =
             rows("SELECT kind FROM phoenix.rails_commands WHERE kind='tracks_changed'")
  end

  test "adopted tracks retain corrected and unrelated source segments", c do
    track = track!(c, nil, 100)

    rows(
      "INSERT INTO points(user_id,import_id,track_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,$3,100,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now()),($1,NULL,$3,200,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now())",
      [c.user, c.id, track]
    )

    rows(
      "INSERT INTO track_segments(track_id,source,start_index,end_index,corrected_at,created_at,updated_at) VALUES($1,'csv',0,1,NULL,now(),now()),($1,'csv',2,3,now(),now(),now()),($1,'other',4,5,NULL,now(),now())",
      [track]
    )

    assert :ok = DestroyWorker.perform(c.job)

    assert [["csv"], ["other"]] =
             rows("SELECT source FROM track_segments WHERE track_id=$1 ORDER BY start_index", [
               track
             ])

    assert [
             [
               "imports.destroy_callbacks",
               %{"step" => "reclassify_tracks", "track_ids" => [track]}
             ]
           ] ==
             rows(
               "SELECT kind,payload FROM phoenix.rails_commands WHERE kind='imports.destroy_callbacks' AND payload->>'step'='reclassify_tracks'"
             )
             |> Enum.map(fn [kind, payload] ->
               [kind, Map.take(payload, ["step", "track_ids"])]
             end)
  end

  test "foreign-user child linkage is refused before deleting or changing status", c do
    rows(
      "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,1,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now())",
      [c.other, c.id]
    )

    assert {:cancel, "foreign import dependents"} = DestroyWorker.perform(c.job)
    assert [[2]] = rows("SELECT status FROM imports WHERE id=$1", [c.id])
    assert [[1]] = rows("SELECT count(*) FROM points WHERE import_id=$1", [c.id])
    assert [] = rows("SELECT id FROM phoenix.rails_commands")
  end

  test "late point-batch failure preserves prior deletion and Rails partial counter retry semantics",
       c do
    rows("UPDATE users SET points_count=10001 WHERE id=$1", [c.user])

    rows(
      "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) SELECT $1,$2,1640995200+i,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now() FROM generate_series(1,10001) AS i",
      [c.user, c.id]
    )

    rows(
      "CREATE OR REPLACE FUNCTION public.reject_last_destroy_point() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF OLD.timestamp=1641005201 THEN RAISE EXCEPTION 'synthetic late batch failure'; END IF; RETURN OLD; END$$"
    )

    rows(
      "CREATE TRIGGER reject_last_destroy_point BEFORE DELETE ON points FOR EACH ROW EXECUTE FUNCTION public.reject_last_destroy_point()"
    )

    on_exit(fn ->
      rows("DROP TRIGGER IF EXISTS reject_last_destroy_point ON points")
      rows("DROP FUNCTION IF EXISTS public.reject_last_destroy_point()")
    end)

    assert_raise Postgrex.Error, fn -> DestroyWorker.perform(c.job) end
    assert [[1]] = rows("SELECT count(*) FROM points WHERE import_id=$1", [c.id])
    assert [[10001]] = rows("SELECT points_count FROM users WHERE id=$1", [c.user])

    assert [[3, 0]] =
             rows("SELECT status,additional_data_extraction_status FROM imports WHERE id=$1", [
               c.id
             ])

    assert [[2]] =
             rows("SELECT count(*) FROM phoenix.rails_commands WHERE kind='points.tile_epoch'")

    refute Processed.done?(ScratchRepo, c.event)
    rows("DROP TRIGGER reject_last_destroy_point ON points")
    rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
    assert :ok = DestroyWorker.perform(%{c.job | attempt: 2})
    assert [[10000]] = rows("SELECT points_count FROM users WHERE id=$1", [c.user])
  end

  test "Sidekiq handback persists fallback before marking the native event", c do
    Ownership.put!(ScratchRepo, "command:imports.destroy", :sidekiq)
    assert :ok = DestroyWorker.perform(c.job)

    assert [[true, "handback"]] =
             rows(
               "SELECT native_fallback,phase FROM phoenix.import_destroy_runs WHERE import_id=$1",
               [c.id]
             )

    assert [
             [
               "imports.destroy_requested",
               %{"event_id" => c.event, "import_id" => c.id, "user_id" => c.user}
             ]
           ] == rows("SELECT kind,payload FROM phoenix.rails_commands")

    assert Processed.done?(ScratchRepo, c.event)
    assert :ok = DestroyWorker.perform(c.job)
    assert [[1]] = rows("SELECT count(*) FROM phoenix.rails_commands")
  end

  test "cancelled actual worker never hands back or marks processed", c do
    rows("UPDATE oban.oban_jobs SET state='cancelled' WHERE id=$1", [c.job.id])
    assert {:cancel, _} = DestroyWorker.perform(c.job)
    refute Processed.done?(ScratchRepo, c.event)
    assert [] = rows("SELECT kind FROM phoenix.rails_commands")
  end

  test "owner transfer during a committed point batch hands back without false failure", c do
    points!(c)

    rows(
      "CREATE OR REPLACE FUNCTION public.transfer_destroy_owner() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN UPDATE phoenix.job_owners SET owner='sidekiq' WHERE key='command:imports.destroy'; RETURN OLD; END$$"
    )

    rows(
      "CREATE TRIGGER transfer_destroy_owner AFTER DELETE ON points FOR EACH STATEMENT EXECUTE FUNCTION public.transfer_destroy_owner()"
    )

    on_exit(fn ->
      rows("DROP TRIGGER IF EXISTS transfer_destroy_owner ON points")
      rows("DROP FUNCTION IF EXISTS public.transfer_destroy_owner()")
    end)

    assert :ok = DestroyWorker.perform(c.job)
    assert [[4]] = rows("SELECT status FROM imports WHERE id=$1", [c.id])
    assert [] = rows("SELECT id FROM points WHERE import_id=$1", [c.id])
    assert [[3]] = rows("SELECT points_count FROM users WHERE id=$1", [c.user])

    assert [[true]] =
             rows("SELECT native_fallback FROM phoenix.import_destroy_runs WHERE import_id=$1", [
               c.id
             ])

    assert [["imports.destroy_requested"]] =
             rows(
               "SELECT kind FROM phoenix.rails_commands WHERE kind='imports.destroy_requested'"
             )

    assert [] =
             rows(
               "SELECT kind FROM phoenix.rails_commands WHERE kind='imports.destroy_status' AND payload->>'status'='failed'"
             )
  end

  test "terminal tombstone permits a current retry after the import is gone", c do
    rows("DELETE FROM imports WHERE id=$1", [c.id])

    rows(
      "INSERT INTO phoenix.import_destroy_runs(import_id,user_id,event_id,phase,context) VALUES($1,$2,$3,'removed',$4)",
      [c.id, c.user, Ecto.UUID.dump!(c.event), %{"track_ids" => []}]
    )

    assert :ok = DestroyWorker.perform(c.job)
    assert Processed.done?(ScratchRepo, c.event)

    assert [[1]] =
             rows(
               "SELECT count(*) FROM phoenix.rails_commands WHERE kind='imports.destroy_stats'"
             )
  end

  test "a terminal tombstone never authorizes deletion of a recreated import", c do
    rows(
      "INSERT INTO phoenix.import_destroy_runs(import_id,user_id,event_id,phase) VALUES($1,$2,$3,'removed')",
      [c.id, c.user, Ecto.UUID.dump!(c.event)]
    )

    assert {:skip, _} =
             DestroyLease.with_import(ScratchRepo, c.job, fn _ ->
               flunk("terminal event acquired recreated row")
             end)

    assert [[2]] = rows("SELECT status FROM imports WHERE id=$1", [c.id])

    assert [["removed"]] =
             rows("SELECT phase FROM phoenix.import_destroy_runs WHERE import_id=$1", [c.id])
  end

  test "terminal tombstone hands back cleanup if the owner changes after row removal", c do
    rows("DELETE FROM imports WHERE id=$1", [c.id])

    rows(
      "INSERT INTO phoenix.import_destroy_runs(import_id,user_id,event_id,phase,context) VALUES($1,$2,$3,'removed',$4)",
      [c.id, c.user, Ecto.UUID.dump!(c.event), %{"track_ids" => []}]
    )

    Ownership.put!(ScratchRepo, "command:imports.destroy", :sidekiq)
    assert :ok = DestroyWorker.perform(c.job)
    assert [["imports.destroy_terminal"]] = rows("SELECT kind FROM phoenix.rails_commands")

    assert [["removed", true]] =
             rows(
               "SELECT phase,native_fallback FROM phoenix.import_destroy_runs WHERE import_id=$1",
               [c.id]
             )
  end

  test "foreign data arriving after admission stops the next guarded effect", c do
    assert {:ok, :stopped} =
             DestroyLease.with_import(ScratchRepo, c.job, fn lease ->
               rows(
                 "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,1,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now())",
                 [c.other, c.id]
               )

               assert_raise LeaseLost, fn ->
                 DestroyLease.effect!(lease, fn ->
                   rows("UPDATE imports SET status=3 WHERE id=$1", [c.id])
                 end)
               end

               :stopped
             end)

    assert [[4]] = rows("SELECT status FROM imports WHERE id=$1", [c.id])
  end

  test "detaches source and prepared files with immutable last-reference purge proofs", c do
    source = blob!("destroy-source")
    prepared = blob!("destroy-prepared")

    rows(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Import',$1,$2,now()),('prepared_download','Import',$1,$3,now())",
      [c.id, source, prepared]
    )

    rows(
      "INSERT INTO phoenix.import_download_requests(import_id,source_blob_id,requested_at,event_id) VALUES($1,$2,now(),$3)",
      [c.id, source, Ecto.UUID.dump!(c.event)]
    )

    assert :ok = DestroyWorker.perform(c.job)

    assert [] =
             rows(
               "SELECT id FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1",
               [c.id]
             )

    assert [] =
             rows("SELECT import_id FROM phoenix.import_download_requests WHERE import_id=$1", [
               c.id
             ])

    assert [[source, c.id, c.user, source], [prepared, c.id, c.user, source]] ==
             rows(
               "SELECT blob_id,import_id,user_id,source_blob_id FROM phoenix.import_blob_purges ORDER BY blob_id"
             )

    assert [[source], [prepared]] ==
             rows(
               "SELECT (payload->>'blob_id')::bigint FROM phoenix.rails_commands WHERE kind='imports.prepared_download_purge' ORDER BY (payload->>'blob_id')::bigint"
             )

    assert [[2]] = rows("SELECT count(*) FROM active_storage_blobs")
  end

  test "shared source attachment is retained and never authorized for purge", c do
    source = blob!("destroy-shared")

    [[other_import]] =
      rows(
        "INSERT INTO imports(user_id,name,source,status,created_at,updated_at) VALUES($1,'shared.csv',10,2,now(),now()) RETURNING id",
        [c.other]
      )

    rows(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Import',$1,$3,now()),('file','Import',$2,$3,now())",
      [c.id, other_import, source]
    )

    assert :ok = DestroyWorker.perform(c.job)

    assert [[^other_import]] =
             rows("SELECT record_id FROM active_storage_attachments WHERE blob_id=$1", [source])

    assert [] = rows("SELECT blob_id FROM phoenix.import_blob_purges")

    assert [] =
             rows(
               "SELECT kind FROM phoenix.rails_commands WHERE kind='imports.prepared_download_purge'"
             )
  end

  test "bulk orphan tracks retain shared links while extracted tracks destroy theirs", c do
    orphan = track!(c, nil, 100)
    extracted = track!(c, c.id, 200)

    rows(
      "INSERT INTO points(user_id,import_id,track_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,$3,100,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now())",
      [c.user, c.id, orphan]
    )

    rows(
      "INSERT INTO shared_links(user_id,resource_type,resource_id,name,created_at,updated_at) VALUES($1,1,$2,'Orphan share',now(),now()),($1,1,$3,'Extracted share',now(),now())",
      [c.user, orphan, extracted]
    )

    assert :ok = DestroyWorker.perform(c.job)
    assert [] = rows("SELECT id FROM tracks WHERE id=ANY($1::bigint[])", [[orphan, extracted]])
    assert [[^orphan]] = rows("SELECT resource_id FROM shared_links WHERE user_id=$1", [c.user])
  end

  for {name, sql, field} <- [
        {"late attempt replacement", "UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", :job},
        {"late user deletion", "UPDATE users SET deleted_at=now() WHERE id=$1", :user},
        {"late token replacement",
         "UPDATE phoenix.import_destroy_runs SET token=gen_random_uuid() WHERE import_id=$1", :id}
      ] do
    test "#{name} stops the next effect and leaves deleting status", c do
      assert {:ok, :stopped} =
               DestroyLease.with_import(ScratchRepo, c.job, fn lease ->
                 value =
                   if unquote(field) == :job, do: c.job.id, else: Map.fetch!(c, unquote(field))

                 rows(unquote(sql), [value])

                 assert_raise LeaseLost, fn ->
                   DestroyLease.effect!(lease, fn ->
                     rows("UPDATE imports SET status=3 WHERE id=$1", [c.id])
                   end)
                 end

                 :stopped
               end)

      assert [[4]] = rows("SELECT status FROM imports WHERE id=$1", [c.id])
      refute Processed.done?(ScratchRepo, c.event)
    end
  end

  test "a lease cannot escape its owning process or invocation", c do
    assert {:ok, lease} =
             DestroyLease.with_import(ScratchRepo, c.job, fn lease ->
               assert Task.async(fn ->
                        assert_raise LeaseLost, fn ->
                          DestroyLease.effect!(lease, fn -> :wrong end)
                        end
                      end)
                      |> Task.await()

               lease
             end)

    assert_raise LeaseLost, fn -> DestroyLease.effect!(lease, fn -> :wrong end) end
  end

  test "tile epoch groups UTC years and accepts nullable int32 timestamps", c do
    stamps = [nil, -2_147_483_648, -1, 0, 1_640_995_199, 1_640_995_200, 2_147_483_647]

    rows(
      "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) SELECT $1,$2,at,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now() FROM unnest($3::bigint[]) AS at",
      [c.user, c.id, stamps]
    )

    assert :ok = DestroyWorker.perform(c.job)

    assert [[payload]] =
             rows("SELECT payload FROM phoenix.rails_commands WHERE kind='points.tile_epoch'")

    assert payload["timestamps"] == [nil, 1_640_995_199, 1_640_995_200, 2_147_483_647]
  end

  test "a completed terminal event cannot be handed back to a recreated import", c do
    rows(
      "INSERT INTO phoenix.import_destroy_runs(import_id,user_id,event_id,phase) VALUES($1,$2,$3,'removed')",
      [c.id, c.user, Ecto.UUID.dump!(c.event)]
    )

    Ownership.put!(ScratchRepo, "command:imports.destroy", :sidekiq)
    assert {:cancel, _} = DestroyWorker.perform(c.job)
    assert [[2]] = rows("SELECT status FROM imports WHERE id=$1", [c.id])
    assert [] = rows("SELECT kind FROM phoenix.rails_commands")
    refute Processed.done?(ScratchRepo, c.event)
  end

  test "enhanced extraction commits completed 500-visit batches before a later failure", c do
    rows("UPDATE imports SET additional_data_extraction_status=2 WHERE id=$1", [c.id])

    [[first, last]] =
      rows(
        "WITH added AS (INSERT INTO visits(user_id,import_id,name,started_at,ended_at,duration,created_at,updated_at) SELECT $1,$2,'Synthetic batch',now()-interval '1 hour',now(),3600,now(),now() FROM generate_series(1,1001) RETURNING id) SELECT min(id),max(id) FROM added",
        [c.user, c.id]
      )

    rows(
      "CREATE OR REPLACE FUNCTION public.reject_last_destroy_visit() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF OLD.name='Reject visit' THEN RAISE EXCEPTION 'synthetic visit batch failure'; END IF; RETURN OLD; END$$"
    )

    rows("UPDATE visits SET name='Reject visit' WHERE id=$1", [last])

    rows(
      "CREATE TRIGGER reject_last_destroy_visit BEFORE DELETE ON visits FOR EACH ROW EXECUTE FUNCTION public.reject_last_destroy_visit()"
    )

    on_exit(fn ->
      rows("DROP TRIGGER IF EXISTS reject_last_destroy_visit ON visits")
      rows("DROP FUNCTION IF EXISTS public.reject_last_destroy_visit()")
    end)

    assert_raise Postgrex.Error, fn -> DestroyWorker.perform(c.job) end
    assert [[^last]] = rows("SELECT id FROM visits WHERE import_id=$1", [c.id])
    assert [] = rows("SELECT id FROM visits WHERE id=$1", [first])

    assert [[3, 2]] =
             rows("SELECT status,additional_data_extraction_status FROM imports WHERE id=$1", [
               c.id
             ])

    assert [[2]] =
             rows("SELECT count(*) FROM phoenix.rails_commands WHERE kind='visit_months_changed'")
  end

  test "nullable import source resets only uncorrected null-source segments", c do
    rows("UPDATE imports SET source=NULL WHERE id=$1", [c.id])
    track = track!(c, nil, 100)

    rows(
      "INSERT INTO points(user_id,import_id,track_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,$3,100,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now()),($1,NULL,$3,200,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now())",
      [c.user, c.id, track]
    )

    rows(
      "INSERT INTO track_segments(track_id,source,start_index,end_index,corrected_at,created_at,updated_at) VALUES($1,NULL,0,1,NULL,now(),now()),($1,NULL,2,3,now(),now(),now()),($1,'csv',4,5,NULL,now(),now())",
      [track]
    )

    assert :ok = DestroyWorker.perform(c.job)

    assert [[nil], ["csv"]] ==
             rows("SELECT source FROM track_segments WHERE track_id=$1 ORDER BY start_index", [
               track
             ])

    assert [[1]] ==
             rows(
               "SELECT count(*) FROM phoenix.rails_commands WHERE kind='imports.destroy_callbacks' AND payload->>'step'='reclassify_tracks'"
             )
  end

  defp blob!(key) do
    [[id]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES($1,'synthetic.csv','text/csv','{}','local',3,'abc',now()) RETURNING id",
        [key]
      )

    id
  end

  defp track!(c, import_id, at) do
    [[id]] =
      rows(
        "INSERT INTO tracks(user_id,import_id,start_at,end_at,original_path,created_at,updated_at) VALUES($1,$2,to_timestamp($3) AT TIME ZONE 'UTC',to_timestamp($3+100) AT TIME ZONE 'UTC',ST_GeomFromText('LINESTRING(10 50,11 51)',4326),now(),now()) RETURNING id",
        [c.user, import_id, at]
      )

    id
  end

  defp points!(c) do
    rows(
      "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) SELECT $1,$2,1640995200+i,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now() FROM generate_series(1,3) AS i",
      [c.user, c.id]
    )
  end
end
