defmodule Dawarich.Users.StandaloneDeletionTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.{AfterCommit, ScratchRepo, Storage}
  alias Dawarich.Jobs.{Dispatch, Ownership, Processed, Registry}
  alias Dawarich.Users.DestroyWorker
  alias Dawarich.Test.RailsUser

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")
    start_oban(__MODULE__)
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    root = Path.join(System.tmp_dir!(), "deletion-#{Ecto.UUID.generate()}")
    File.mkdir_p!(root)

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")

      File.rm_rf!(root)
    end)

    actor =
      RailsUser.insert!(
        %{
          id: System.unique_integer([:positive]),
          email: "delete-#{Ecto.UUID.generate()}@example.invalid",
          deleted_at: NaiveDateTime.utc_now()
        },
        ScratchRepo
      )

    other =
      RailsUser.insert!(
        %{
          id: System.unique_integer([:positive]),
          email: "keep-#{Ecto.UUID.generate()}@example.invalid"
        },
        ScratchRepo
      )

    %{actor: actor, other: other, root: root}
  end

  @tag :sa_destroy_dispatch
  test "standalone typed deletion dispatches and coexistence retains its owner", c do
    assert Registry.command("users.destroy") == {:ok, DestroyWorker}
    assert DestroyWorker.enqueue(ScratchRepo, c.actor.id) == {:error, :transaction_required}

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn -> DestroyWorker.enqueue(ScratchRepo, c.actor.id) end)

    assert %{dispatched: 1} = Dispatch.run(repo: ScratchRepo, oban: __MODULE__)
    assert %{success: 1, failure: 0} = Oban.drain_queue(__MODULE__, queue: :maintenance)
    assert rows("SELECT id FROM users WHERE id=$1", [c.actor.id]) == []
    assert rows("SELECT id FROM users WHERE id=$1", [c.other.id]) == [[c.other.id]]
    assert rows("SELECT state,error_code FROM job_outbox") == [["dispatched", nil]]
    System.delete_env("DAWARICH_RAILS")
    Ownership.put!(ScratchRepo, "command:users.destroy", :sidekiq)

    assert {:ok, {:error, :worker_owner}} =
             ScratchRepo.transaction(fn -> DestroyWorker.enqueue(ScratchRepo, c.other.id) end)

    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
  end

  @tag :sa_destroy_effects
  test "deletion commits purge and after-commit intents once and storage failure keeps its ledger",
       c do
    [[import]] =
      rows(
        "INSERT INTO imports(user_id,name,created_at,updated_at) VALUES($1,'synthetic',now(),now()) RETURNING id",
        [c.actor.id]
      )

    key = Storage.generate_key()
    path = Storage.disk_path(c.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "synthetic")

    [[blob]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,metadata,service_name,byte_size,created_at) VALUES($1,'synthetic','{}','test',9,now()) RETURNING id",
        [key]
      )

    rows(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Import',$1,$2,now())",
      [import, blob]
    )

    cache_key = "dawarich/user_#{c.actor.id}_total_distance"
    assert {:ok, "OK"} = Dawarich.Redis.cache_command(["SET", cache_key, "synthetic"])
    args = %{"user_id" => c.actor.id, "event_id" => Ecto.UUID.generate()}

    rows(
      "CREATE FUNCTION sa_refuse_deletion() RETURNS trigger AS $$ BEGIN RAISE EXCEPTION 'synthetic cleanup failure'; END; $$ LANGUAGE plpgsql"
    )

    rows(
      "CREATE TRIGGER sa_cleanup_failure BEFORE DELETE ON users FOR EACH ROW EXECUTE FUNCTION sa_refuse_deletion()"
    )

    try do
      assert {:error, {:cleanup, :raise_exception}} = DestroyWorker.run(ScratchRepo, args)
      refute Processed.done?(ScratchRepo, args["event_id"])
      assert rows("SELECT id FROM imports WHERE id=$1", [import]) == [[import]]

      assert rows("SELECT blob_id FROM active_storage_attachments WHERE record_id=$1", [import]) ==
               [[blob]]

      assert rows("SELECT id FROM oban.oban_jobs") == []
    after
      rows("DROP TRIGGER sa_cleanup_failure ON users")
      rows("DROP FUNCTION sa_refuse_deletion()")
    end

    parent = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> DestroyWorker.run(ScratchRepo, args)
          end
        end)
      end

    for task <- tasks do
      pid = task.pid
      assert_receive {:ready, ^pid}
    end

    for task <- tasks, do: send(task.pid, :go)
    for task <- tasks, do: assert(:ok == Task.await(task))
    assert :ok = DestroyWorker.run(ScratchRepo, args)
    assert Processed.done?(ScratchRepo, args["event_id"])
    assert rows("SELECT id FROM users WHERE id=$1", [c.other.id]) == [[c.other.id]]

    assert [[cache]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [
               Oban.Worker.to_string(AfterCommit.Worker)
             ])

    assert {:ok, "synthetic"} = Dawarich.Redis.cache_command(["GET", cache_key])
    refute ScratchRepo.in_transaction?()
    stop_supervised!(Dawarich.Redis.Cache)
    assert {:error, _} = AfterCommit.Worker.run(ScratchRepo, cache)
    refute Processed.done?(ScratchRepo, cache["intent_id"])
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    assert {:ok, "synthetic"} = Dawarich.Redis.cache_command(["GET", cache_key])
    assert :ok = AfterCommit.Worker.run(ScratchRepo, cache)
    assert :ok = AfterCommit.Worker.run(ScratchRepo, cache)
    assert {:ok, nil} = Dawarich.Redis.cache_command(["GET", cache_key])
    assert cache["operation"] == "keys"
    assert cache["payload"]["user_id"] == c.actor.id
    assert "dawarich/user_#{c.actor.id}_total_distance" in cache["payload"]["keys"]

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Users.DestructionWebhookWorker'"
           ) == [[1]]

    assert [[purge]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker'")

    assert File.exists?(path)
    File.rm!(path)
    File.mkdir!(path)
    config = %{service: "local", root: c.root}

    assert {:error, {:storage_delete, _}} =
             Dawarich.Exports.PurgeWorker.run(purge,
               repo: ScratchRepo,
               resolve_service: fn _ -> {:ok, config} end
             )

    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob]) == [[blob]]
    File.rmdir!(path)
    File.write!(path, "synthetic")

    assert :ok =
             Dawarich.Exports.PurgeWorker.run(purge,
               repo: ScratchRepo,
               resolve_service: fn _ -> {:ok, config} end
             )

    refute File.exists?(path)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob]) == []

    assert :ok =
             Dawarich.Exports.PurgeWorker.run(purge,
               repo: ScratchRepo,
               resolve_service: fn _ -> {:ok, config} end
             )
  end
end
