defmodule Dawarich.Imports.DestroyRecoveryTest do
  use Dawarich.JobsCase

  alias Dawarich.Imports.Destroy
  alias Dawarich.Jobs.{Dispatch, Ownership}

  setup do
    saved = Application.fetch_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

    on_exit(fn ->
      case saved do
        {:ok, value} -> Application.put_env(:dawarich, :jobs_repo, value)
        :error -> Application.delete_env(:dawarich, :jobs_repo)
      end
    end)

    [[user]] =
      rows(
        "INSERT INTO users(email,points_count,created_at,updated_at) VALUES('recover-delete@example.test',1,now(),now()) RETURNING id"
      )

    [[id]] =
      rows(
        "INSERT INTO imports(user_id,name,source,status,created_at,updated_at) VALUES($1,'abandoned.csv',10,4,now(),now()) RETURNING id",
        [user]
      )

    rows(
      "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,100,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now())",
      [user, id]
    )

    Ownership.put!(ScratchRepo, "command:imports.destroy", :oban)
    %{user: user, id: id, context: %{zone: "UTC", locale: "en"}}
  end

  test "inherited deleting row without any receipt is dispatched and really deleted", c do
    assert {:ok, :queued} = Destroy.enqueue(ScratchRepo, c.user, c.id, c.context)
    finish!(c)
  end

  for state <- ~w(cancelled discarded completed) do
    test "#{state} destruction receives a successor event and completes", c do
      old = receipt!(c)
      job!(c, old, unquote(state))
      assert {:ok, :queued} = Destroy.enqueue(ScratchRepo, c.user, c.id, c.context)

      assert [[event]] =
               rows("SELECT event_id::text FROM phoenix.import_destroy_runs WHERE import_id=$1", [
                 c.id
               ])

      refute event == old
      finish!(c)
    end
  end

  for state <- ~w(available scheduled retryable executing) do
    test "#{state} current destruction is deduplicated", c do
      event = receipt!(c)
      job!(c, event, unquote(state))
      assert {:ok, :queued} = Destroy.enqueue(ScratchRepo, c.user, c.id, c.context)
      assert [] = rows("SELECT event_id FROM job_outbox")

      assert [[^event]] =
               rows("SELECT event_id::text FROM phoenix.import_destroy_runs WHERE import_id=$1", [
                 c.id
               ])
    end
  end

  test "Sidekiq retries inherited deleting imports and deduplicates its durable request", c do
    Ownership.put!(ScratchRepo, "command:imports.destroy", :sidekiq)
    assert {:ok, :queued} = Destroy.enqueue(ScratchRepo, c.user, c.id, c.context)

    assert [["imports.destroy_requested", payload]] =
             rows("SELECT kind,payload FROM phoenix.rails_commands")

    assert payload["import_id"] == c.id
    assert payload["user_id"] == c.user
    assert {:ok, :queued} = Destroy.enqueue(ScratchRepo, c.user, c.id, c.context)
    assert [[1]] = rows("SELECT count(*) FROM phoenix.rails_commands")
  end

  test "an orphan pending command cannot block recovery through its dedupe key", c do
    old =
      outbox!(
        command_type: "imports.destroy",
        payload: %{"import_id" => c.id, "user_id" => c.user},
        aggregate_id: c.id,
        dedupe_key: "destroy-import:#{c.id}"
      )

    assert {:ok, :queued} = Destroy.enqueue(ScratchRepo, c.user, c.id, c.context)

    assert [["quarantined", "superseded_destroy"]] =
             rows("SELECT state,error_code FROM job_outbox WHERE event_id=$1", [
               Ecto.UUID.dump!(old)
             ])

    finish!(c)
  end

  test "a recreated import cannot reuse a completed tombstone", c do
    receipt!(c)
    rows("UPDATE phoenix.import_destroy_runs SET phase='removed' WHERE import_id=$1", [c.id])
    assert {:error, :not_found} = Destroy.enqueue(ScratchRepo, c.user, c.id, c.context)
    assert [] = rows("SELECT event_id FROM job_outbox")
  end

  test "an executing Sidekiq deletion holds the actual shared lock and is not superseded", c do
    event = receipt!(c)
    Ownership.put!(ScratchRepo, "command:imports.destroy", :sidekiq)
    parent = self()

    task =
      Task.async(fn ->
        ScratchRepo.checkout(fn ->
          rows("SELECT pg_advisory_lock(hashtextextended($1,0))", ["phoenix-import:#{c.id}"])
          send(parent, :deleting)

          receive do
            :release -> :ok
          end

          rows("SELECT pg_advisory_unlock(hashtextextended($1,0))", ["phoenix-import:#{c.id}"])
        end)
      end)

    assert_receive :deleting

    try do
      assert {:ok, :queued} = Destroy.enqueue(ScratchRepo, c.user, c.id, c.context)

      assert [[^event]] =
               rows("SELECT event_id::text FROM phoenix.import_destroy_runs WHERE import_id=$1", [
                 c.id
               ])

      assert [] = rows("SELECT kind FROM phoenix.rails_commands")
    after
      send(task.pid, :release)
      Task.await(task)
    end
  end

  test "recovery retains original orphan track ids after a committed point batch", c do
    [[track]] =
      rows(
        "INSERT INTO tracks(user_id,start_at,end_at,original_path,created_at,updated_at) VALUES($1,now()-interval '1 hour',now(),ST_GeomFromText('LINESTRING(10 50,11 51)',4326),now(),now()) RETURNING id",
        [c.user]
      )

    receipt!(c, %{"track_ids" => [track], "time_zone" => "Pacific/Auckland", "locale" => "fr"})
    assert {:ok, :queued} = Destroy.enqueue(ScratchRepo, c.user, c.id, c.context)

    assert [[context]] =
             rows("SELECT context FROM phoenix.import_destroy_runs WHERE import_id=$1", [c.id])

    assert context["track_ids"] == [track]
    assert context["time_zone"] == "Pacific/Auckland"
    finish!(c)
    assert [] = rows("SELECT id FROM tracks WHERE id=$1", [track])
  end

  defp receipt!(c, context \\ %{}) do
    event = Ecto.UUID.generate()

    rows(
      "INSERT INTO phoenix.import_destroy_runs(import_id,user_id,event_id,phase,context) VALUES($1,$2,$3,'deleting',$4)",
      [c.id, c.user, Ecto.UUID.dump!(event), context]
    )

    event
  end

  defp job!(c, event, state) do
    rows(
      "INSERT INTO oban.oban_jobs(state,queue,worker,args,attempt,max_attempts) VALUES($1,'imports','Dawarich.Imports.DestroyWorker',$2,1,3)",
      [state, %{"import_id" => c.id, "user_id" => c.user, "event_id" => event}]
    )
  end

  defp finish!(c) do
    start_oban(__MODULE__)
    assert [[scheduled]] = rows("SELECT scheduled_at FROM job_outbox WHERE state='pending'")

    assert %{dispatched: 1} =
             Dispatch.run(repo: ScratchRepo, oban: __MODULE__, now: DateTime.add(scheduled, 1))

    assert %{success: 1, failure: 0} = Oban.drain_queue(__MODULE__, queue: :imports)
    assert [] = rows("SELECT id FROM imports WHERE id=$1", [c.id])
    assert [] = rows("SELECT id FROM points WHERE import_id=$1", [c.id])
  end
end
