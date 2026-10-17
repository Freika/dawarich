defmodule Dawarich.A12f3bE13SharedVariantTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.{ScratchRepo, Storage}
  alias Dawarich.Exports.PurgeWorker
  alias Dawarich.Jobs.{Drain, Ownership}

  setup do
    root = Path.join(System.tmp_dir!(), "shared-variant-" <> Ecto.UUID.generate())
    previous = Application.fetch_env!(:dawarich, :rails_root)
    env = Map.take(System.get_env(), ~w(DAWARICH_RAILS STORAGE_BACKEND))
    Application.put_env(:dawarich, :rails_root, root)
    System.delete_env("STORAGE_BACKEND")
    start_oban(__MODULE__)

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_root, previous)

      for key <- ~w(DAWARICH_RAILS STORAGE_BACKEND) do
        if env[key], do: System.put_env(key, env[key]), else: System.delete_env(key)
      end

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  for mode <- [:standalone, :coexistence] do
    @tag a12f3b_case: "F4-#{mode}"
    test "F4 #{mode} poster purge recovers every shared variant target and preserves surviving references",
         c do
      set_mode!(unquote(mode))

      for survivor <- [:none, :variant_failure, :external_parent, :late_attachment] do
        [[user]] =
          rows(
            "INSERT INTO users(email,created_at,updated_at) VALUES($1,now(),now()) RETURNING id",
            [Ecto.UUID.generate() <> "@shared-variant.test"]
          )

        [[poster]] =
          rows(
            "INSERT INTO posters(name,status,settings,user_id,created_at,updated_at) VALUES('synthetic',0,'{}',$1,now(),now()) RETURNING id",
            [user]
          )

        {a, a_file} = blob!(c.root)
        {b, b_file} = blob!(c.root)
        {child, child_file} = blob!(c.root)
        {leaf, leaf_file} = blob!(c.root)
        attach!("image", "Poster", poster, a)
        attach!("print_pdf", "Poster", poster, b)
        variants = [variant!(a, child), variant!(b, child), variant!(child, leaf)]

        external =
          if survivor == :external_parent do
            {parent, file} = blob!(c.root)
            attach!("image", "Poster", poster + 1_000_000, parent)
            {parent, file, variant!(parent, child)}
          end

        assert {:ok, ^poster} =
                 Dawarich.Posters.Persistence.delete(poster, %{id: user}, ScratchRepo)

        [[job_id, args]] =
          rows(
            "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker' ORDER BY id DESC LIMIT 1"
          )

        if survivor == :late_attachment,
          do: attach!("image", "Poster", poster + 1_000_000, child)

        File.rm!(a_file)
        File.mkdir!(a_file)
        assert %{success: 0, failure: 1} = Oban.drain_queue(__MODULE__, queue: :exports)
        retained!([a, b, child, leaf], variants)

        assert [["retryable", 1, 1]] =
                 rows(
                   "SELECT state,attempt,cardinality(errors) FROM oban.oban_jobs WHERE id=$1",
                   [job_id]
                 )

        assert Drain.status(ScratchRepo).counts.incomplete_oban == 1

        assert %{success: 0, failure: 1} =
                 Oban.drain_queue(__MODULE__, queue: :exports, with_scheduled: true)

        retained!([a, b, child, leaf], variants)
        File.rmdir!(a_file)
        File.write!(a_file, "synthetic media")

        if survivor == :variant_failure do
          File.rm!(child_file)
          File.mkdir!(child_file)

          assert %{success: 0, failure: 1} =
                   Oban.drain_queue(__MODULE__, queue: :exports, with_scheduled: true)

          retained!([a, b, child, leaf], variants)
          refute File.exists?(a_file) or File.exists?(b_file)
          assert File.exists?(child_file) and File.exists?(leaf_file)

          assert %{success: 0, failure: 1} =
                   Oban.drain_queue(__MODULE__, queue: :exports, with_scheduled: true)

          retained!([a, b, child, leaf], variants)
          assert Drain.status(ScratchRepo).counts.incomplete_oban == 1
          File.rmdir!(child_file)
          File.write!(child_file, "synthetic variant")
        end

        assert %{success: 1, failure: 0} =
                 Oban.drain_queue(__MODULE__, queue: :exports, with_scheduled: true)

        assert :ok = PurgeWorker.perform(%Oban.Job{args: Jason.decode!(Jason.encode!(args))})
        refute File.exists?(a_file) or File.exists?(b_file)
        assert rows("SELECT id FROM active_storage_blobs WHERE id=ANY($1)", [[a, b]]) == []

        assert rows("SELECT id FROM active_storage_variant_records WHERE id=ANY($1)", [
                 Enum.take(variants, 2)
               ]) == []

        if survivor in [:none, :variant_failure] do
          refute File.exists?(child_file) or File.exists?(leaf_file)

          assert rows("SELECT id FROM active_storage_blobs WHERE id=ANY($1)", [[child, leaf]]) ==
                   []

          assert rows("SELECT id FROM active_storage_attachments WHERE blob_id=ANY($1)", [
                   [child, leaf]
                 ]) == []

          assert rows("SELECT id FROM active_storage_variant_records WHERE id=ANY($1)", [variants]) ==
                   []

          assert Enum.sort(Enum.map(args["objects"], & &1["blob_id"])) ==
                   Enum.sort([a, b, child, leaf])
        else
          assert File.exists?(child_file) and File.exists?(leaf_file)
          retained!([child, leaf], [List.last(variants)])

          assert length(
                   rows("SELECT id FROM active_storage_attachments WHERE blob_id=$1", [child])
                 ) == 1

          if external do
            {parent, file, variant} = external
            assert File.exists?(file)
            retained!([parent], [variant])
            assert Enum.sort(Enum.map(args["objects"], & &1["blob_id"])) == Enum.sort([a, b])
          end
        end

        assert [["completed"]] = rows("SELECT state FROM oban.oban_jobs WHERE id=$1", [job_id])
        assert Drain.status(ScratchRepo).counts.incomplete_oban == 0
        assert rows("SELECT kind FROM phoenix.rails_commands") == []
      end
    end
  end

  defp set_mode!(mode) do
    if mode == :standalone,
      do: System.put_env("DAWARICH_RAILS", "off"),
      else: System.delete_env("DAWARICH_RAILS")

    owner = if mode == :standalone, do: :sidekiq, else: :oban
    Ownership.put!(ScratchRepo, "command:posters.create", owner, pinned: true)
  end

  defp retained!(blobs, variants) do
    assert rows("SELECT id FROM active_storage_blobs WHERE id=ANY($1) ORDER BY id", [blobs]) ==
             Enum.map(Enum.sort(blobs), &[&1])

    assert rows("SELECT id FROM active_storage_variant_records WHERE id=ANY($1) ORDER BY id", [
             variants
           ]) ==
             Enum.map(Enum.sort(variants), &[&1])
  end

  defp variant!(parent, child) do
    [[id]] =
      rows(
        "INSERT INTO active_storage_variant_records(blob_id,variation_digest) VALUES($1,$2) RETURNING id",
        [parent, Ecto.UUID.generate()]
      )

    attach!("image", "ActiveStorage::VariantRecord", id, child)
    id
  end

  defp attach!(name, type, id, blob),
    do:
      rows(
        "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES($1,$2,$3,$4,now())",
        [name, type, id, blob]
      )

  defp blob!(root) do
    key = Storage.generate_key()

    [[id]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,created_at) VALUES($1,'synthetic','image/png','{\"identified\":true,\"analyzed\":true}','local',15,now()) RETURNING id",
        [key]
      )

    file = Storage.disk_path(Path.join(root, "storage"), key)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, "synthetic media")
    {id, file}
  end
end
