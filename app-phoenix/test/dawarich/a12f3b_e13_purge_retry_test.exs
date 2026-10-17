defmodule Dawarich.A12f3bE13PurgeRetryTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.{ScratchRepo, Storage}
  alias Dawarich.Jobs.{Drain, Processed}
  alias Dawarich.Posters.{Command, PurgeWorker}

  setup do
    root = Path.join(System.tmp_dir!(), "media-purge-#{System.unique_integer([:positive])}")
    previous = Application.fetch_env!(:dawarich, :rails_root)
    rails = System.get_env("DAWARICH_RAILS")
    Application.put_env(:dawarich, :rails_root, root)
    System.put_env("DAWARICH_RAILS", "off")
    start_oban(__MODULE__)

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_root, previous)

      if rails,
        do: System.put_env("DAWARICH_RAILS", rails),
        else: System.delete_env("DAWARICH_RAILS")

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  @tag a12f3b_case: "F1"
  test "F1 captured poster purge retains failed storage work until retry and drain completion",
       c do
    state = File.read!("test/fixtures/posters/points_gap_boundaries.json") |> Jason.decode!()
    poster = state["before"]["id"]
    user = state["actor_id"]

    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES($1,'purge-retry@example.test',now(),now())",
      [user]
    )

    for failure <- [:disk, :missing_service] do
      {blob, path} = blob!(c.root)
      {child, child_path} = blob!(c.root)

      [[variant]] =
        rows(
          "INSERT INTO active_storage_variant_records(blob_id,variation_digest) VALUES($1,$2) RETURNING id",
          [blob, Ecto.UUID.generate()]
        )

      attach!("ActiveStorage::VariantRecord", variant, child)
      args = enqueue!(poster, user, [blob])

      case failure do
        :disk ->
          File.rm!(path)
          File.mkdir!(path)
          assert %{success: 0, failure: 1} = Oban.drain_queue(__MODULE__, queue: :posters)

        :missing_service ->
          assert_raise KeyError, fn ->
            PurgeWorker.run(ScratchRepo, args, services: %{services: %{}})
          end
      end

      assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob]) == [[blob]]

      assert rows("SELECT id FROM active_storage_variant_records WHERE id=$1", [variant]) == [
               [variant]
             ]

      assert rows("SELECT blob_id FROM active_storage_attachments WHERE record_id=$1", [variant]) ==
               [[child]]

      refute Processed.done?(ScratchRepo, args["event_id"])
      assert File.exists?(path)
      assert File.exists?(child_path)
      assert Drain.status(ScratchRepo).counts.incomplete_oban == 1
      assert "incomplete_oban" in Drain.status(ScratchRepo).shutdown_reasons

      if failure == :disk do
        File.rmdir!(path)
        File.write!(path, "synthetic media")
      end

      File.rm!(child_path)
      File.mkdir!(child_path)

      assert %{success: 0, failure: 1} =
               Oban.drain_queue(__MODULE__, queue: :posters, with_scheduled: true)

      assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob]) == [[blob]]
      refute Processed.done?(ScratchRepo, args["event_id"])
      assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [child]) == [[child]]
      assert Drain.status(ScratchRepo).counts.incomplete_oban == 1
      File.rmdir!(child_path)
      File.write!(child_path, "synthetic variant")

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(__MODULE__, queue: :posters, with_scheduled: true)

      refute File.exists?(path)
      assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob]) == []
      assert rows("SELECT id FROM active_storage_variant_records WHERE id=$1", [variant]) == []
      assert Processed.done?(ScratchRepo, args["event_id"])
      refute File.exists?(child_path)
      assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [child]) == []
      assert :ok = PurgeWorker.run(ScratchRepo, args)
      assert Drain.status(ScratchRepo).counts.incomplete_oban == 0
      refute "incomplete_oban" in Drain.status(ScratchRepo).shutdown_reasons
    end

    {shared, shared_path} = blob!(c.root)
    attach!("Export", poster, shared)
    enqueue!(poster, user, [shared])
    assert %{success: 1, failure: 0} = Oban.drain_queue(__MODULE__, queue: :posters)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [shared]) == [[shared]]
    assert File.exists?(shared_path)

    rows(
      "INSERT INTO posters SELECT * FROM json_populate_record(NULL::posters,$1::text::json)",
      [Jason.encode!(state["before"])]
    )

    {guarded, guarded_path} = blob!(c.root)
    enqueue!(poster, user, [guarded])
    assert %{success: 1, failure: 0} = Oban.drain_queue(__MODULE__, queue: :posters)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [guarded]) == [[guarded]]
    assert File.exists?(guarded_path)
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
  end

  defp enqueue!(poster, user, blobs) do
    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               Command.purge(ScratchRepo, :sidekiq, %{
                 "poster_id" => poster,
                 "user_id" => user,
                 "blob_ids" => blobs
               })
             end)

    [[args]] =
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Posters.PurgeWorker' ORDER BY id DESC LIMIT 1"
      )

    args
  end

  defp attach!(type, id, blob),
    do:
      rows(
        "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file',$1,$2,$3,now())",
        [type, id, blob]
      )

  defp blob!(root) do
    key = Storage.generate_key()
    path = Storage.disk_path(Path.join(root, "storage"), key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "synthetic media")

    [[id]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,created_at) VALUES($1,'synthetic.png','image/png','{}','local',15,now()) RETURNING id",
        [key]
      )

    {id, path}
  end
end
