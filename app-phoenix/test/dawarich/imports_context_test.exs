defmodule Dawarich.ImportsContextTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db
  alias Dawarich.{Imports, Storage, Uploads}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.RailsUser

  setup do
    user = RailsUser.insert!(%{id: 10942, email: "imports-owner@example.invalid"}, ScratchRepo)
    other = RailsUser.insert!(%{id: 10943, email: "imports-other@example.invalid"}, ScratchRepo)
    root = Path.join(System.tmp_dir!(), "scoped-imports-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    for command <-
          ~w(imports.process_gpx imports.process_normal users.import_data imports.destroy enhanced_import.extract_gpx enhanced_import.destroy_gpx),
        do: Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:" <> command, :oban)

    storage = %{service: "local", root: root}

    %{
      scope: Scope.for_user(user, "en"),
      other: Scope.for_user(other, "en"),
      storage: storage,
      opts: [repo: ScratchRepo, services: %{"local" => storage}]
    }
  end

  defp uploaded(c, name, bytes) do
    assert {:ok, ref} =
             Uploads.reserve(
               c.scope,
               %{
                 filename: name,
                 byte_size: byte_size(bytes),
                 checksum: Base.encode64(:crypto.hash(:md5, bytes)),
                 content_type: "application/gpx+xml"
               },
               %{repo: ScratchRepo, storage: c.storage, kind: :imports}
             )

    [[key]] =
      rows(
        "SELECT b.key FROM active_storage_blobs b JOIN phoenix.native_uploads u ON u.blob_id=b.id WHERE u.reference=$1",
        [ref]
      )

    path = Storage.disk_path(c.storage.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
    ref
  end

  test "import commands refuse forged ids and stale entitlement without effects", c do
    ref = uploaded(c, "owned.gpx", "<gpx/>")
    assert {:ok, [id]} = apply(Imports, :create, [c.scope, [ref], c.opts])

    assert {:error, :not_found} =
             apply(Imports, :update, [c.other, id, %{"name" => "forged"}, c.opts])

    assert {:error, :not_found} = apply(Imports, :delete, [c.other, id, c.opts])
    rows("UPDATE users SET active_until=now()-interval '1 second' WHERE id=$1", [c.scope.user.id])

    assert {:error, :inactive} =
             apply(Imports, :update, [c.scope, id, %{"name" => "expired"}, c.opts])

    assert [["owned.gpx", 0]] = rows("SELECT name,status FROM imports WHERE id=$1", [id])

    rows(
      "UPDATE users SET active_until=now()+interval '1 day',encrypted_password='rotated' WHERE id=$1",
      [c.scope.user.id]
    )

    assert {:error, :stale_session} = apply(Imports, :delete, [c.scope, id, c.opts])
    assert [] = rows("SELECT import_id FROM phoenix.import_destroy_runs")
  end

  test "multi-file claim rolls back every attachment and publication on one invalid entry", c do
    refs = for _ <- 1..3, do: uploaded(c, "duplicate.gpx", "<gpx/>")
    assert {:error, :duplicate_name} = apply(Imports, :create, [c.scope, refs, c.opts])
    assert [] = rows("SELECT id FROM imports")
    assert [] = rows("SELECT id FROM active_storage_attachments")
    assert [] = rows("SELECT event_id FROM job_outbox")
    assert [] = rows("SELECT id FROM oban.oban_jobs WHERE worker='Dawarich.Imports.EventsWorker'")
    assert [[3]] = rows("SELECT count(*) FROM phoenix.native_uploads WHERE state='pending'")
  end

  test "duplicate upload submission publishes the accepted batch once", c do
    refs = [uploaded(c, "first.gpx", "<gpx/>"), uploaded(c, "second.gpx", "<gpx/>")]
    assert {:ok, ids} = apply(Imports, :create, [c.scope, refs, c.opts])
    assert length(ids) == 2
    assert {:error, :claimed} = apply(Imports, :create, [c.scope, refs, c.opts])
    assert [[2]] = rows("SELECT count(*) FROM imports")

    assert [[2]] =
             rows("SELECT count(*) FROM job_outbox WHERE command_type='imports.process_gpx'")

    assert [[2]] = rows("SELECT count(*) FROM active_storage_attachments")
  end

  test "committed import intents survive rollback replay and contain only owner identity", c do
    ref = uploaded(c, "events.gpx", "<gpx/>")
    assert {:ok, [id]} = apply(Imports, :create, [c.scope, [ref], c.opts])
    assert :ok = apply(Imports, :subscribe, [c.scope, c.opts])

    assert [[args]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Imports.EventsWorker'")

    assert Enum.sort(Map.keys(args)) == ["event_id", "user_id"]

    assert {:error, :abort} =
             ScratchRepo.transaction(fn ->
               assert {:ok, :updated} =
                        apply(Imports, :update, [c.scope, id, %{"name" => "rolled back"}, c.opts])

               ScratchRepo.rollback(:abort)
             end)

    refute_receive {:domain_changed, _, _}
    assert [["events.gpx"]] = rows("SELECT name FROM imports WHERE id=$1", [id])

    assert [[1]] =
             rows(
               "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Imports.EventsWorker'"
             )

    assert :ok = Dawarich.Imports.EventsWorker.run(ScratchRepo, args)
    assert_receive {:domain_changed, owner, :imports}
    assert owner == c.scope.user.id
    assert :ok = Dawarich.Imports.EventsWorker.run(ScratchRepo, args)
    refute_receive {:domain_changed, _, _}
  end

  test "scoped snapshots retain sort and extraction facts without raw traces or capabilities",
       c do
    ref = uploaded(c, "snapshot.gpx", "<gpx/>")
    assert {:ok, [id]} = apply(Imports, :create, [c.scope, [ref], c.opts])

    rows("UPDATE imports SET raw_data=$2,additional_data_extraction=$3 WHERE id=$1", [
      id,
      %{
        "waypoints_seen" => 0,
        "trackpoints_seen" => 1,
        "route_points_seen" => 0,
        "private_trace" => "synthetic"
      },
      %{"counts" => %{"tracks" => 1}, "private_trace" => "synthetic"}
    ])

    assert {:ok, record} = apply(Imports, :get, [c.scope, id, c.opts])
    refute Map.has_key?(record, :raw_data)
    assert record.no_waypoints?
    assert record.additional_data_extraction == %{"counts" => %{"tracks" => 1}}
    assert {:error, :not_found} = apply(Imports, :get, [c.other, id, c.opts])
    list = %{column: "name", direction: :asc, page: 1}

    assert {:ok, %{entries: [%{id: ^id, name: "snapshot.gpx"}], total_pages: 1}} =
             apply(Imports, :page, [c.scope, list, c.opts])

    assert {:error, :invalid_list} =
             apply(Imports, :page, [c.scope, %{list | column: "forged"}, c.opts])
  end

  test "native imports refuse unavailable producer ownership without a Rails handback", c do
    ref = uploaded(c, "ownership.gpx", "<gpx/>")
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.process_gpx", :sidekiq)
    assert {:error, :not_owned} = apply(Imports, :create, [c.scope, [ref], c.opts])
    assert [] = rows("SELECT id FROM imports")
    assert [] = rows("SELECT event_id FROM job_outbox")
    assert [] = rows("SELECT id FROM phoenix.rails_commands")

    assert [["pending"]] =
             rows("SELECT state FROM phoenix.native_uploads WHERE reference=$1", [ref])
  end
end
