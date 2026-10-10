defmodule Dawarich.A12f3bG02Test do
  use Dawarich.JobsCase

  alias Dawarich.Families.{InvitationCleanupWorker, LocationRequestExpiryWorker}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.PendingImports.{CleanupWorker, PurgeWorker}
  alias Dawarich.Storage

  @oban __MODULE__.Oban
  @now ~U[2026-10-04 12:00:00Z]

  defmodule RollbackRepo do
    def transaction(fun) do
      if Dawarich.ScratchRepo.in_transaction?() do
        Dawarich.ScratchRepo.transaction(fun)
      else
        Dawarich.ScratchRepo.transaction(fn ->
          fun.()

          snapshot =
            Dawarich.ScratchRepo.query!(
              "SELECT (SELECT count(*) FROM family_invitations WHERE status=0), (SELECT count(*) FROM family_location_requests WHERE status=0), (SELECT count(*) FROM oban.oban_jobs)",
              [],
              log: false
            ).rows

          send(self(), {:before_housekeeping_rollback, snapshot})
          Dawarich.ScratchRepo.rollback(:interrupted)
        end)
      end
    end

    defdelegate in_transaction?(), to: Dawarich.ScratchRepo
    defdelegate insert!(changeset, opts), to: Dawarich.ScratchRepo

    def query!(sql, args, opts), do: Dawarich.ScratchRepo.query!(sql, args, opts)
    def update_all(query, opts), do: Dawarich.ScratchRepo.update_all(query, opts)
    def delete_all(query), do: Dawarich.ScratchRepo.delete_all(query)
  end

  setup do
    start_oban(@oban)
    root = Path.join(System.tmp_dir!(), "cron-storage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, services: %{services: %{"test" => %{service: "local", root: root}}}}
  end

  @tag a12f3b_case: "G02a"
  test "housekeeping crons preserve expiry scope and atomically roll back native invalidations" do
    for name <-
          ~w(nightly_family_invitations_cleanup_job family_location_requests_expiry_job pending_imports_cleanup route_videos_purge_job stale_jobs_recovery_job) do
      assert %{kind: :cron, catch_up: false} =
               Enum.find(Dawarich.Jobs.Registry.entries(), &(&1.key == "cron:" <> name))
    end

    [[user]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES ('cron-family@example.test',now(),now()) RETURNING id"
      )

    [[family]] =
      rows(
        "INSERT INTO families(name,creator_id,created_at,updated_at) VALUES ('Cron',$1,now(),now()) RETURNING id",
        [user]
      )

    rows(
      "INSERT INTO family_memberships(family_id,user_id,created_at,updated_at) VALUES($1,$2,now(),now())",
      [family, user]
    )

    for {expires, expected} <- [
          {NaiveDateTime.add(DateTime.to_naive(@now), -1), 3},
          {DateTime.to_naive(@now), 3},
          {NaiveDateTime.add(DateTime.to_naive(@now), 1), 0}
        ] do
      [[id]] =
        rows(
          "INSERT INTO family_location_requests(family_id,requester_id,target_user_id,status,expires_at,created_at,updated_at) VALUES ($1,$2,$2,0,$3,now(),now()) RETURNING id",
          [family, user, expires]
        )

      Ownership.put!(ScratchRepo, LocationRequestExpiryWorker.key(), :oban)
      assert LocationRequestExpiryWorker.run(ScratchRepo, DateTime.to_naive(@now)) == :ok
      assert rows("SELECT status FROM family_location_requests WHERE id=$1", [id]) == [[expected]]
    end

    assert rows(
             "SELECT worker,args->>'kind',(args->>'user_id')::bigint,state FROM oban.oban_jobs ORDER BY id"
           ) ==
             List.duplicate(["Dawarich.Families.EventsWorker", "request", user, "available"], 2)

    rows(
      "INSERT INTO family_invitations(family_id,invited_by_id,email,token,status,expires_at,created_at,updated_at) VALUES($1,$2,'cron-invite@example.test',$3,0,$4,$5,$5)",
      [
        family,
        user,
        Ecto.UUID.generate(),
        NaiveDateTime.add(DateTime.to_naive(@now), -1),
        DateTime.to_naive(@now)
      ]
    )

    rows(
      "INSERT INTO family_location_requests(family_id,requester_id,target_user_id,status,expires_at,created_at,updated_at) VALUES($1,$2,$2,0,$3,$3,$3)",
      [family, user, DateTime.to_naive(@now)]
    )

    for worker <- [InvitationCleanupWorker, LocationRequestExpiryWorker] do
      Ownership.put!(ScratchRepo, worker.key(), :oban)
      before = footprint()
      assert worker.run(RollbackRepo, DateTime.to_naive(@now)) == {:error, :interrupted}
      assert footprint() == before
      expected = if worker == InvitationCleanupWorker, do: [[0, 2, 3]], else: [[1, 1, 3]]
      assert_received {:before_housekeeping_rollback, ^expected}
      Ownership.put!(ScratchRepo, worker.key(), :sidekiq, pinned: true)
      assert worker.run(ScratchRepo, DateTime.to_naive(@now)) == {:cancel, :not_owner}
      assert footprint() == before
    end
  end

  defp footprint do
    {
      rows("SELECT id,status,updated_at FROM family_invitations ORDER BY id"),
      rows("SELECT id,status,updated_at FROM family_location_requests ORDER BY id"),
      rows("SELECT id,worker,args,state,scheduled_at FROM oban.oban_jobs ORDER BY id"),
      rows("SELECT event_id,command_type,payload FROM job_outbox ORDER BY event_id")
    }
  end

  @tag a12f3b_case: "G02b"
  test "housekeeping failed purge remains visible and cannot delete shared blob", %{
    root: root,
    services: services
  } do
    Ownership.put!(ScratchRepo, CleanupWorker.key(), :oban)

    rows(
      "INSERT INTO pending_imports(id,original_filename,origin,expires_at,created_at,updated_at) VALUES (901,'synthetic.zip','synthetic',$1,now(),now())",
      [DateTime.to_naive(@now)]
    )

    rows(
      "INSERT INTO active_storage_blobs(id,key,filename,service_name,byte_size,created_at) VALUES (902,'cronpurge','synthetic.zip','test',1,now())"
    )

    rows(
      "INSERT INTO active_storage_attachments(id,name,record_type,record_id,blob_id,created_at) VALUES (903,'file','PendingImport',901,902,now())"
    )

    path = Storage.disk_path(root, "cronpurge")
    File.mkdir_p!(path)
    File.write!(Path.join(path, "keep"), "synthetic")
    assert CleanupWorker.run(ScratchRepo, @oban, @now, services: services) == :ok

    [[args]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.PendingImports.PurgeWorker'")

    assert {:error, {:storage_delete, _}} = PurgeWorker.run(ScratchRepo, args, services: services)
    assert rows("SELECT id FROM pending_imports") == [[901]]
    assert rows("SELECT id FROM active_storage_blobs") == [[902]]

    rows(
      "INSERT INTO active_storage_attachments(id,name,record_type,record_id,blob_id,created_at) VALUES (904,'file','Import',905,902,now())"
    )

    assert PurgeWorker.run(ScratchRepo, args, services: services) == :ok
    assert rows("SELECT record_type FROM active_storage_attachments") == [["Import"]]
    assert File.exists?(Path.join(path, "keep"))

    rows(
      "INSERT INTO pending_imports(id,original_filename,origin,expires_at,created_at,updated_at) SELECT n,'synthetic.zip','synthetic',$1,now(),now() FROM generate_series(1001,2001) n",
      [DateTime.to_naive(@now)]
    )

    parent = self()
    handler = "cron-continuation-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:dawarich, :scratch_repo, :query],
      fn _, _, meta, _ ->
        if meta.query == "DELETE FROM pending_imports WHERE id=$1" and meta.params == [2000] do
          send(parent, :last_cleanup)
          Ownership.put!(ScratchRepo, CleanupWorker.key(), :sidekiq, pinned: true)
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert CleanupWorker.run(ScratchRepo, @oban, @now, services: services) ==
             {:cancel, :not_owner}

    assert_received :last_cleanup
    assert rows("SELECT id FROM pending_imports") == [[2001]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end
end
