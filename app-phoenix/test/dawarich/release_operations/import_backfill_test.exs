defmodule Dawarich.ReleaseOperations.ImportBackfillTest do
  use Dawarich.JobsCase
  alias Dawarich.ReleaseOperations.ImportBackfill
  alias Dawarich.Test.ActivityBackfillFixtures, as: F
  alias Dawarich.Wave6Fixtures
  alias __MODULE__.ActivityFailureRepo

  @now ~U[2026-01-15 23:30:00.000000Z]

  setup do
    root = Path.join(System.tmp_dir!(), "a12rel-worker-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

    sequences =
      Map.new(
        ~w(tracks track_segments),
        &{&1, rows("SELECT last_value,is_called FROM #{&1}_id_seq")}
      )

    on_exit(fn ->
      cleanup()

      for {table, [[value, called]]} <- sequences,
          do: rows("SELECT setval('#{table}_id_seq',$1,$2)", [value, called])

      if previous,
        do: Application.put_env(:dawarich, :jobs_repo, previous),
        else: Application.delete_env(:dawarich, :jobs_repo)

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "release import reprocesses supported tracks after missing or invalid activity files", c do
    for profile <- F.corpus()["cases"] do
      cleanup()
      F.seed!(profile)

      Wave6Fixtures.track!(987_001, %{
        "id" => 56201,
        "dominant_mode" => 5,
        "start_at" => DateTime.to_naive(@now),
        "end_at" => DateTime.to_naive(DateTime.add(@now, 600)),
        "updated_at" => ~N[2026-01-14 23:30:00]
      })

      rows("UPDATE points SET track_id=56201 WHERE import_id=987101")
      attach(profile, c.root)
      before = F.snapshot()
      imports = rows("SELECT to_jsonb(i) FROM imports i ORDER BY id")
      event = Ecto.UUID.generate()

      args = %{
        "version" => 1,
        "event_id" => event,
        "import_id" => if(profile["id"] == "missing", do: 999_999, else: 987_101),
        "ambient_zone" => "Europe/Berlin"
      }

      context = %{
        services: %{"local" => %{service: "local", root: c.root}},
        temp_dir: c.root,
        now: @now
      }

      repo =
        if profile["id"] in ~w(sql_failure phone_sql_failure),
          do: ActivityFailureRepo,
          else: ScratchRepo

      Process.put(:a12rel_activity_updates, 0)
      Process.put(:a12rel_phone_failure, profile["id"] == "phone_sql_failure")

      case profile["id"] do
        "shape_error" ->
          assert_raise ArgumentError, fn -> ImportBackfill.run(repo, args, context) end

        failure when failure in ~w(sql_failure phone_sql_failure) ->
          assert_raise Postgrex.Error, fn -> ImportBackfill.run(repo, args, context) end

        _ ->
          assert ImportBackfill.run(repo, args, context) == :ok
      end

      if profile["id"] in ~w(checksum size empty),
        do: F.assert_points(profile["before"]),
        else: F.assert_points(profile["after"])

      F.assert_untouched(before)
      assert imports == rows("SELECT to_jsonb(i) FROM imports i ORDER BY id")
      assert F.committed_snapshot() == F.snapshot()

      assert rows("SELECT count(*) FROM phoenix.rails_commands WHERE kind='tracks_changed'") == [
               [if(profile["track_calls"] == [], do: 0, else: 1)]
             ]

      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
      assert rows("SELECT count(*) FROM phoenix.notification_events") == [[0]]
      assert Dawarich.Jobs.Processed.done?(ScratchRepo, event) == is_nil(profile["error"])

      if profile["id"] in ~w(sql_failure phone_sql_failure) do
        F.assert_points(profile["observed"])
        assert rows("SELECT dominant_mode FROM tracks WHERE id=56201") == [[5]]
        assert rows("SELECT count(*) FROM track_segments WHERE track_id=56201") == [[0]]
        assert ImportBackfill.run(ScratchRepo, args, context) == :ok
        F.assert_points(profile["retry"]["after"])
        assert Dawarich.Jobs.Processed.done?(ScratchRepo, event)

        assert rows("SELECT count(*) FROM phoenix.rails_commands WHERE kind='tracks_changed'") ==
                 [[1]]
      end

      if is_nil(profile["error"]) do
        state = F.snapshot()
        assert ImportBackfill.run(repo, args, context) == :ok
        assert F.snapshot() == state
      end

      rows("DELETE FROM phoenix.rails_commands")
    end

    cleanup()
    profile = F.profile("absent")
    F.seed!(profile)

    assert ImportBackfill.perform(%Oban.Job{
             args: %{
               "version" => 1,
               "event_id" => Ecto.UUID.generate(),
               "import_id" => 987_101,
               "ambient_zone" => "Europe/Berlin"
             }
           }) == :ok
  end

  defmodule ActivityFailureRepo do
    def query!(sql, params, opts \\ []) do
      if String.starts_with?(sql, "UPDATE points SET motion_data") do
        count = Process.get(:a12rel_activity_updates, 0) + 1
        Process.put(:a12rel_activity_updates, count)

        failure = if Process.get(:a12rel_phone_failure), do: hd(params) == 56304, else: count == 2

        if failure,
          do: Dawarich.ScratchRepo.query!("UPDATE points SET a12rel_missing_column=1", [], opts)
      end

      Dawarich.ScratchRepo.query!(sql, params, opts)
    end
  end

  defp cleanup do
    rows("DELETE FROM active_storage_attachments WHERE record_type='Import' AND record_id=987101")
    rows("DELETE FROM active_storage_blobs WHERE id=56501")
    rows("DELETE FROM points WHERE user_id=987001")
    rows("DELETE FROM track_segments WHERE track_id=56201")
    rows("DELETE FROM tracks WHERE id=56201")
    F.cleanup()
  end

  defp attach(%{"input" => nil}, _root), do: :ok

  defp attach(profile, root) do
    bytes = F.input(profile)
    key = "a12rel_" <> profile["id"]
    path = Dawarich.Storage.disk_path(root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
    if profile["id"] == "download_error", do: File.rm!(path)

    ScratchRepo.insert_all("active_storage_blobs", [
      %{
        id: 56501,
        key: key,
        filename: "synthetic.json",
        byte_size: byte_size(bytes) + if(profile["id"] == "size", do: 1, else: 0),
        checksum:
          Base.encode64(
            :crypto.hash(:md5, if(profile["id"] == "checksum", do: "other bytes", else: bytes))
          ),
        service_name: "local",
        created_at: DateTime.to_naive(@now)
      }
    ])

    ScratchRepo.insert_all("active_storage_attachments", [
      %{
        id: 56601,
        name: "file",
        record_type: "Import",
        record_id: 987_101,
        blob_id: 56501,
        created_at: DateTime.to_naive(@now)
      }
    ])
  end
end
