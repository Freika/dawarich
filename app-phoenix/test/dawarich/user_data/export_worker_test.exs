defmodule Dawarich.UserData.ExportWorkerTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.UserDataSeeds
  alias Dawarich.UserData.ExportWorker
  alias Dawarich.Jobs.{Ownership, Processed, Registry}
  @key "command:users.export_data"

  setup do
    rows("DELETE FROM countries WHERE id=988991")

    rows(
      "TRUNCATE places, areas, tags, taggings, visits, tracks, track_segments, digests, points_raw_data_archives CASCADE"
    )

    c = UserDataSeeds.seed!("UTC", ScratchRepo)
    rows("DELETE FROM exports WHERE id=988202")
    rows("SELECT setval(pg_get_serial_sequence('exports','id'),988202,false)")
    :ok = Ownership.put!(ScratchRepo, @key, :oban)

    secret =
      "test/fixtures/rails_cookies.json"
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("rails_test_secret")

    context =
      c.context
      |> Map.put(:archive_key, Dawarich.RawData.ArchiveFormat.key(%{}, secret))
      |> Map.put(:application_zone, "Europe/Berlin")

    args = %{
      "event_id" => Ecto.UUID.generate(),
      "user_id" => c.user_id,
      "time_zone" => "UTC",
      "locale" => "en"
    }

    %{c: c, context: context, args: args}
  end

  test "backup worker writes processing completed attachment and exact notification once", %{
    c: c,
    context: context,
    args: args
  } do
    assert {:ok, ExportWorker} == Registry.command("users.export_data")
    refute Enum.any?(Registry.claimable(), &(&1.key == @key))
    assert ExportWorker.new(Map.drop(args, ["event_id"])).changes.max_attempts == 1
    assert {:ok, payload} = ExportWorker.args_from_command(1, Map.drop(args, ["event_id"]))
    assert payload["time_zone"] == "UTC"

    assert {:error, "invalid_payload"} =
             ExportWorker.args_from_command(1, %{"user_id" => c.user_id})

    assert {:error, "unsupported_version"} = ExportWorker.args_from_command(2, payload)
    assert :ok = ExportWorker.run(ScratchRepo, args, context: context)

    assert [[988_202, 2, 2, 1, nil, ~N[2026-10-02 12:00:00.000000]]] =
             rows(
               "SELECT id,status,file_format,file_type,error_message,processing_started_at FROM exports WHERE id=988202"
             )

    assert [[key, filename]] =
             rows(
               "SELECT b.key,b.filename FROM active_storage_blobs b JOIN active_storage_attachments a ON a.blob_id=b.id WHERE a.record_type='Export' AND a.record_id=988202"
             )

    assert filename == "user_data_export_20261002_120000.zip"
    path = Dawarich.Storage.disk_path(context.storage.root, key)
    assert {:ok, extracted} = :zip.unzip(String.to_charlist(path), [:memory])

    assert Map.new(extracted, fn {name, bytes} -> {List.to_string(name), bytes} end) ==
             UserDataSeeds.current_export_entries("UTC")

    expected = c.expected["notifications"] |> Enum.find(&(&1["title"] == "Export completed"))

    assert [[expected["title"], expected["content"], 0]] ==
             rows(
               "SELECT title,content,kind FROM notifications WHERE user_id=$1 AND title='Export completed'",
               [c.user_id]
             )

    assert Processed.done?(ScratchRepo, args["event_id"])
    assert :ok = ExportWorker.run(ScratchRepo, args, context: context)
    assert [[2]] == rows("SELECT count(*) FROM exports WHERE user_id=$1", [c.user_id])
    assert [[1]] == rows("SELECT count(*) FROM notifications WHERE title='Export completed'")
    assert File.ls!(Path.join(context.storage.root, ".phoenix-tmp")) == []
    assert [] == rows("SELECT command_type FROM job_outbox")
    rows("UPDATE users SET deleted_at=$2 WHERE id=$1", [c.user_id, context.now])

    assert :ok =
             ExportWorker.run(ScratchRepo, %{args | "event_id" => Ecto.UUID.generate()},
               context: context
             )

    assert [[2]] == rows("SELECT count(*) FROM exports WHERE user_id=$1", [c.user_id])

    assert :ok =
             ExportWorker.run(
               ScratchRepo,
               %{args | "event_id" => Ecto.UUID.generate(), "user_id" => 99_999_999},
               context: context
             )
  end

  @tag :export_redelivery
  test "backup and export redelivery purge every generation storage before rows", %{
    context: context,
    args: args,
    c: c
  } do
    previous = System.get_env("DAWARICH_RAILS")

    try do
      for mode <-
            Enum.filter(
              ["on", "off"],
              &(System.get_env("DAWARICH_REDELIVERY_TEST_MODE", &1) == &1)
            ) do
        System.put_env("DAWARICH_RAILS", mode)
        event = %{args | "event_id" => Ecto.UUID.generate()}
        notify = fn _, _, _, _, _ -> throw(:simulated_shutdown) end

        assert catch_throw(ExportWorker.run(ScratchRepo, event, context: context, notify: notify)) ==
                 :simulated_shutdown

        refute Processed.done?(ScratchRepo, event["event_id"])

        [[id]] =
          rows("SELECT export_id FROM phoenix.export_claims WHERE event_id=$1", [
            Ecto.UUID.dump!(event["event_id"])
          ])

        [[old_id, old_key]] =
          rows(
            "SELECT b.id,b.key FROM active_storage_blobs b JOIN active_storage_attachments a ON a.blob_id=b.id WHERE a.record_type='Export' AND a.record_id=$1",
            [id]
          )

        assert :ok = ExportWorker.run(ScratchRepo, event, context: context)
        assert Processed.done?(ScratchRepo, event["event_id"])

        generations =
          rows(
            "SELECT blob_id FROM active_storage_attachments WHERE record_type='Export' AND record_id=$1 ORDER BY blob_id",
            [id]
          )
          |> List.flatten()

        assert old_id in generations
        assert length(generations) == 2

        shared =
          Dawarich.RailsBlobFixture.create!(
            ScratchRepo,
            context.storage.root,
            "shared.zip",
            "synthetic shared export"
          )

        for record <- [id, 988_203_999],
            do:
              rows(
                "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('shared','Export',$1,$2,now())",
                [record, shared.id]
              )

        variant =
          Dawarich.RailsBlobFixture.create!(
            ScratchRepo,
            context.storage.root,
            "variant.zip",
            "synthetic variant"
          )

        leaf =
          Dawarich.RailsBlobFixture.create!(
            ScratchRepo,
            context.storage.root,
            "leaf.zip",
            "synthetic descendant"
          )

        for {parent, child} <- [{old_id, variant.id}, {variant.id, leaf.id}] do
          [[variant_record]] =
            rows(
              "INSERT INTO active_storage_variant_records(blob_id,variation_digest) VALUES($1,'synthetic') RETURNING id",
              [parent]
            )

          rows(
            "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('image','ActiveStorage::VariantRecord',$1,$2,now())",
            [variant_record, child]
          )
        end

        [[leaf_key]] = rows("SELECT key FROM active_storage_blobs WHERE id=$1", [leaf.id])
        assert {:ok, :deleted} = Dawarich.Exports.Delete.call(ScratchRepo, c.user_id, id)

        assert [] == rows("SELECT kind FROM phoenix.rails_commands WHERE kind='exports.purge'")

        [[purge]] =
          rows(
            "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker' ORDER BY id DESC LIMIT 1"
          )

        queued_ids = generations ++ [variant.id, leaf.id]

        assert Enum.sort(queued_ids) ==
                 rows("SELECT id FROM active_storage_blobs WHERE id=ANY($1) ORDER BY id", [
                   queued_ids
                 ])
                 |> List.flatten()

        rows(
          "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('late-reference','Export',988203998,$1,now())",
          [variant.id]
        )

        path = Dawarich.Storage.disk_path(context.storage.root, old_key)
        File.rm!(path)
        File.mkdir_p!(path)

        assert {:error, _} =
                 Dawarich.Exports.PurgeWorker.run(purge,
                   services: %{default: "local", services: context.storage_services},
                   repo: ScratchRepo
                 )

        assert [[old_id]] == rows("SELECT id FROM active_storage_blobs WHERE id=$1", [old_id])
        File.rmdir!(path)
        File.write!(path, "synthetic retry")

        assert :ok =
                 Dawarich.Exports.PurgeWorker.run(purge,
                   services: %{default: "local", services: context.storage_services},
                   repo: ScratchRepo
                 )

        assert :ok =
                 Dawarich.Exports.PurgeWorker.run(purge,
                   services: %{default: "local", services: context.storage_services},
                   repo: ScratchRepo
                 )

        assert [] == rows("SELECT id FROM active_storage_blobs WHERE id=ANY($1)", [generations])
        refute File.exists?(path)

        assert [[variant.id], [leaf.id]] ==
                 rows("SELECT id FROM active_storage_blobs WHERE id=ANY($1) ORDER BY id", [
                   [variant.id, leaf.id]
                 ])

        assert File.regular?(Dawarich.Storage.disk_path(context.storage.root, leaf_key))

        [[variant_metadata], [leaf_metadata]] =
          rows("SELECT metadata FROM active_storage_blobs WHERE id=ANY($1) ORDER BY id", [
            [variant.id, leaf.id]
          ])

        refute Dawarich.Storage.Blobs.purging?(variant_metadata)
        refute Dawarich.Storage.Blobs.purging?(leaf_metadata)

        assert [[shared.id]] ==
                 rows("SELECT id FROM active_storage_blobs WHERE id=$1", [shared.id])

        [[shared_key]] = rows("SELECT key FROM active_storage_blobs WHERE id=$1", [shared.id])
        assert File.regular?(Dawarich.Storage.disk_path(context.storage.root, shared_key))

        [[point_id]] =
          rows(
            "INSERT INTO exports(user_id,name,file_format,file_type,status,created_at,updated_at) VALUES($1,'points',0,0,0,now(),now()) RETURNING id",
            [c.user_id]
          )

        first =
          Dawarich.RailsBlobFixture.create!(
            ScratchRepo,
            context.storage.root,
            "old-points.zip",
            "synthetic prior points"
          )

        rows(
          "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Export',$1,$2,now())",
          [point_id, first.id]
        )

        [[first_key]] = rows("SELECT key FROM active_storage_blobs WHERE id=$1", [first.id])
        point_event = Ecto.UUID.generate()

        assert {:run, point_export} =
                 Dawarich.Exports.claim(ScratchRepo, point_id, c.user_id, point_event)

        temp = Path.join(context.storage.root, "synthetic-new-points")
        File.write!(temp, "synthetic new points")
        next = Dawarich.Storage.put!(context.storage, temp, "new-points.zip", "application/zip")

        assert :ok =
                 Dawarich.Exports.complete(ScratchRepo, point_export, point_event, next, %{
                   title: "Export finished",
                   content: "Synthetic points"
                 })

        point_blobs =
          rows(
            "SELECT blob_id FROM active_storage_attachments WHERE record_type='Export' AND record_id=$1",
            [point_id]
          )
          |> List.flatten()

        assert first.id in point_blobs
        assert length(point_blobs) == 2
        Ownership.put!(ScratchRepo, "command:exports.points", :oban)
        assert {:ok, :deleted} = Dawarich.Exports.Delete.call(ScratchRepo, c.user_id, point_id)

        assert [] == rows("SELECT kind FROM phoenix.rails_commands WHERE kind='exports.purge'")

        [[point_purge]] =
          rows(
            "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker' ORDER BY id DESC LIMIT 1"
          )

        assert :ok =
                 Dawarich.Exports.PurgeWorker.run(point_purge,
                   services: %{default: "local", services: context.storage_services},
                   repo: ScratchRepo
                 )

        assert [] == rows("SELECT id FROM active_storage_blobs WHERE id=ANY($1)", [point_blobs])
        refute File.exists?(Dawarich.Storage.disk_path(context.storage.root, first_key))
        refute File.exists?(Dawarich.Storage.disk_path(context.storage.root, next.key))
      end
    after
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end
  end

  test "backup worker failure and owner loss leave no false completed export", %{
    c: c,
    context: context,
    args: args
  } do
    put = fn _storage, _zip, _name ->
      assert [[1]] == rows("SELECT status FROM exports WHERE id=988202")
      raise "synthetic storage failure"
    end

    assert_raise RuntimeError, "synthetic storage failure", fn ->
      ExportWorker.run(ScratchRepo, args, context: context, put: put)
    end

    assert [[3, nil]] == rows("SELECT status,error_message FROM exports WHERE id=988202")

    assert [] ==
             rows(
               "SELECT id FROM active_storage_attachments WHERE record_type='Export' AND record_id=988202"
             )

    assert [[1]] == rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.user_id])
    assert File.ls!(Path.join(context.storage.root, ".phoenix-tmp")) == []
    notify = fn _repo, _user, _counts, _locale, _now -> raise "synthetic notification failure" end
    next = %{args | "event_id" => Ecto.UUID.generate()}

    assert_raise RuntimeError, "synthetic notification failure", fn ->
      ExportWorker.run(ScratchRepo, next, context: context, notify: notify)
    end

    assert [[3]] == rows("SELECT status FROM exports WHERE id=988203")

    assert [[1]] ==
             rows(
               "SELECT count(*) FROM active_storage_attachments WHERE record_type='Export' AND record_id=988203"
             )

    assert [[1]] == rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.user_id])

    put = fn storage, zip, name ->
      blob = Dawarich.Storage.put!(storage, zip, name, "application/zip")
      Ownership.put!(ScratchRepo, @key, :sidekiq)
      blob
    end

    lost = %{args | "event_id" => Ecto.UUID.generate()}

    assert {:cancel, :ownership_lost} =
             ExportWorker.run(ScratchRepo, lost, context: context, put: put)

    assert [[1]] == rows("SELECT status FROM exports WHERE id=988204")
    refute Processed.done?(ScratchRepo, lost["event_id"])

    assert [] ==
             rows(
               "SELECT id FROM active_storage_attachments WHERE record_type='Export' AND record_id=988204"
             )

    assert File.ls!(Path.join(context.storage.root, ".phoenix-tmp")) == []
    Ownership.put!(ScratchRepo, @key, :oban)

    for {change, id} <- [
          {fn ->
             Ownership.put!(ScratchRepo, @key, :sidekiq)
             Ownership.put!(ScratchRepo, @key, :oban)
           end, 988_205},
          {fn ->
             rows(
               "UPDATE phoenix.leases SET expires_at=statement_timestamp()-interval '1 second'"
             )
           end, 988_206},
          {fn -> rows("UPDATE users SET deleted_at=$2 WHERE id=$1", [c.user_id, context.now]) end,
           988_207}
        ] do
      event = %{args | "event_id" => Ecto.UUID.generate()}

      put = fn storage, zip, name ->
        blob = Dawarich.Storage.put!(storage, zip, name, "application/zip")
        change.()
        blob
      end

      assert {:cancel, :ownership_lost} =
               ExportWorker.run(ScratchRepo, event, context: context, put: put)

      assert [[1]] == rows("SELECT status FROM exports WHERE id=$1", [id])
      refute Processed.done?(ScratchRepo, event["event_id"])

      assert [] ==
               rows(
                 "SELECT id FROM active_storage_attachments WHERE record_type='Export' AND record_id=$1",
                 [id]
               )
    end
  end
end
