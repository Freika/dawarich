defmodule Dawarich.Jobs.A12relCorpusTest do
  use Dawarich.JobsCase
  alias Dawarich.ReleaseOperations.{ImportBackfill, Achievements}
  alias Dawarich.Test.ActivityBackfillFixtures, as: F
  alias Dawarich.Test.{ActivityBackfillFixtures, ApiGolden}
  alias Dawarich.Achievements.Registry
  alias Dawarich.Tracks.{ImportReprocessor}
  alias Dawarich.Transportation.Segments
  alias Dawarich.Wave6Fixtures
  alias __MODULE__.{ActivityFailureRepo, DetectorFailureRepo}
  @oban __MODULE__.Oban
  @dir Path.expand("../../fixtures/a12rel", __DIR__)
  @now ~U[2026-01-15 23:30:00.000000Z]
  @achievement_now ~U[2026-10-04 12:00:00.000000Z]
  @event "00000000-0000-4000-8000-000000540001"
  @args %{"version" => 1, "event_id" => @event}
  @valid "ST_Multi(ST_GeomFromText('POLYGON((0 0,1 0,1 1,0 1,0 0))',4326))"

  test "release adapters match every Rails parent activity and track projection" do
    c = import_setup()
    import_corpus(c)
    import_cleanup()
    track_setup()
    track_corpus()
    track_cleanup()
    Dawarich.JobsCase.reset!(ScratchRepo)
    achievement_setup()
    achievement_failures()
    rows("DELETE FROM countries")
    rows("DELETE FROM regions")
    rows("DELETE FROM oban.oban_jobs")
    rows("DELETE FROM phoenix.processed_commands")
    achievement_successes()
  end

  defp import_setup do
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
      import_cleanup()

      for {table, [[value, called]]} <- sequences,
          do: rows("SELECT setval('#{table}_id_seq',$1,$2)", [value, called])

      if previous,
        do: Application.put_env(:dawarich, :jobs_repo, previous),
        else: Application.delete_env(:dawarich, :jobs_repo)

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  defp import_corpus(c) do
    for profile <- F.corpus()["cases"] do
      import_cleanup()
      F.seed!(profile)

      Wave6Fixtures.track!(987_001, %{
        "id" => 56201,
        "dominant_mode" => 5,
        "start_at" => DateTime.to_naive(@now),
        "end_at" => DateTime.to_naive(DateTime.add(@now, 600)),
        "updated_at" => ~N[2026-01-14 23:30:00]
      })

      rows("UPDATE points SET track_id=56201 WHERE import_id=987101")
      import_attach(profile, c.root)
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

    import_cleanup()
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

  defp import_cleanup do
    rows("DELETE FROM active_storage_attachments WHERE record_type='Import' AND record_id=987101")
    rows("DELETE FROM active_storage_blobs WHERE id=56501")
    rows("DELETE FROM points WHERE user_id=987001")
    rows("DELETE FROM track_segments WHERE track_id=56201")
    rows("DELETE FROM tracks WHERE id=56201")
    F.cleanup()
  end

  defp import_attach(%{"input" => nil}, _root), do: :ok

  defp import_attach(profile, root) do
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

  defp track_setup do
    foreign_keys =
      rows(
        "SELECT conname,pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='points'::regclass AND confrelid='tracks'::regclass"
      )

    sequences =
      Map.new(
        ~w(track_segments tracks),
        &{&1, rows("SELECT last_value,is_called FROM #{&1}_id_seq")}
      )

    on_exit(fn ->
      rows("DROP TRIGGER IF EXISTS a12rel_track_failure ON track_segments")
      rows("DROP FUNCTION IF EXISTS a12rel_track_failure()")
      track_cleanup()

      for [name, definition] <- foreign_keys do
        if rows("SELECT count(*) FROM pg_constraint WHERE conname=$1", [name]) == [[0]],
          do: rows("ALTER TABLE points ADD CONSTRAINT #{name} #{definition}")
      end

      for {table, [[value, called]]} <- sequences do
        rows("SELECT setval('#{table}_id_seq',$1,$2)", [value, called])
      end
    end)

    :ok
  end

  defp track_corpus do
    for name <-
          ~w(selection preservation empty fallback sql_failure unchanged nil_user deleted_user) do
      profile = track_fixture(name)
      track_seed!(profile)
      rows("DELETE FROM phoenix.rails_commands WHERE kind='tracks_changed'")

      repo =
        if name in ~w(fallback sql_failure unchanged), do: DetectorFailureRepo, else: ScratchRepo

      caller = self()

      opts = [
        now: @now,
        report: fn id, error -> send(caller, {:track_error, id, error.__struct__}) end
      ]

      opts =
        if name == "empty", do: Keyword.put(opts, :detector, fn _, _, _ -> [] end), else: opts

      Process.put(:a12rel_track_failure, name == "sql_failure")

      assert ImportReprocessor.run(repo, 987_101, opts) == profile["attempted"]

      for id <- 56_201..56_204 do
        track_assert_track(profile["after"], id)
        track_assert_segments(profile["after"], id)
      end

      track_assert_full_snapshot(profile["after"])
      assert track_committed_snapshot() == track_snapshot()

      commands = rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")

      assert Enum.map(commands, fn [kind, payload] ->
               assert kind == "tracks_changed"
               assert payload["created"] == []
               assert payload["destroyed"] == []
               [payload["user_id"], payload["min_ts"], payload["max_ts"]]
             end) == profile["tile_ranges"]

      assert Enum.flat_map(commands, fn [_, payload] -> payload["updated"] end) ==
               Enum.map(profile["broadcasts"], & &1["payload"]["track"]["id"])

      assert rows("SELECT count(*) FROM phoenix.rails_commands WHERE kind='transport_progress'") ==
               [[0]]

      if name == "sql_failure" do
        assert_receive {:track_error, 56_202, Postgrex.Error}
        Process.delete(:a12rel_track_failure)
        assert ImportReprocessor.run(repo, 987_101, opts) == profile["retry"]["attempted"]
        track_assert_full_snapshot(profile["retry"]["after"])
      else
        refute_receive {:track_error, _, _}, 0
      end
    end

    profile = track_fixture("selection")
    track_seed!(profile)

    [[constraint, _]] =
      rows(
        "SELECT conname,pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='points'::regclass AND confrelid='tracks'::regclass"
      )

    rows("ALTER TABLE points DROP CONSTRAINT #{constraint}")
    rows("UPDATE points SET track_id=56999 WHERE id=56398")
    assert ImportReprocessor.run(ScratchRepo, 987_101, now: @now) == 3
    assert ImportReprocessor.run(ScratchRepo, 999_999, now: @now) == 0
  end

  defmodule DetectorFailureRepo do
    defdelegate transaction(fun), to: Dawarich.ScratchRepo
    defdelegate rollback(reason), to: Dawarich.ScratchRepo

    def query!(sql, params, opts \\ []) do
      cond do
        String.contains?(sql, "p.id AS point_id") ->
          raise("A12rel feature failure")

        Process.get(:a12rel_track_failure) &&
          String.starts_with?(sql, "INSERT INTO track_segments") && hd(params) == 56_202 ->
          Dawarich.ScratchRepo.query!(
            "UPDATE track_segments SET a12rel_missing_column=1",
            [],
            opts
          )

        true ->
          Dawarich.ScratchRepo.query!(sql, params, opts)
      end
    end
  end

  defp track_fixture(name) do
    @dir
    |> Path.join("track_batches.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("cases")
    |> Enum.find(&(&1["id"] == name))
  end

  defp track_seed!(profile) do
    track_cleanup()
    source = ActivityBackfillFixtures.profile("semantic")

    ActivityBackfillFixtures.seed!(%{
      source
      | "before" => Map.put(source["before"], "points", [])
    })

    rows("UPDATE users SET settings=$1 WHERE id=987001", [
      %{"enabled_transportation_modes" => ["walking", "cycling"]}
    ])

    if profile["id"] in ["nil_user", "deleted_user"],
      do: rows("UPDATE users SET deleted_at=$1 WHERE id=987001", [DateTime.to_naive(@now)])

    for row <- profile["before"]["tracks"] do
      row =
        row
        |> then(&ApiGolden.column_defaults("tracks", &1))
        |> Map.put("original_path", row["ewkb"])
        |> Map.delete("ewkb")
        |> Map.update!("dominant_mode", &Segments.mode_to_int/1)

      ApiGolden.insert!("tracks", row, ScratchRepo)
    end

    for row <- profile["before"]["segments"],
        do: ApiGolden.insert!("track_segments", row, ScratchRepo)

    for row <- profile["points"] do
      row = row |> Map.put("lonlat", row["ewkb"]) |> Map.delete("ewkb")
      ApiGolden.insert!("points", row, ScratchRepo)
    end

    rows("SELECT setval('track_segments_id_seq',56500,false)")
  end

  defp track_cleanup do
    rows("DELETE FROM points WHERE user_id=987001")
    rows("DELETE FROM track_segments WHERE track_id BETWEEN 56201 AND 56204")
    rows("DELETE FROM tracks WHERE id BETWEEN 56201 AND 56204")
    ActivityBackfillFixtures.cleanup()
  end

  defp track_snapshot do
    for {table, column} <- [{"tracks", "original_path"}, {"track_segments", "path"}],
        do:
          rows(
            "SELECT to_jsonb(t) || jsonb_build_object('#{column}',encode(ST_AsEWKB(#{column}),'hex')) FROM #{table} t ORDER BY id"
          )
  end

  defp track_committed_snapshot do
    ScratchRepo.checkout(fn ->
      [[first]] = rows("SELECT pg_backend_pid()")

      {second, data} =
        Task.async(fn ->
          ScratchRepo.checkout(fn ->
            [[pid]] = rows("SELECT pg_backend_pid()")
            {pid, track_snapshot()}
          end)
        end)
        |> Task.await()

      assert first != second
      data
    end)
  end

  defp track_assert_full_snapshot(expected) do
    [tracks, segments] = track_snapshot()

    actual_tracks =
      Enum.map(tracks, fn [row] ->
        digest = row["map_matching_input_digest"]
        assert is_nil(digest) or (is_binary(digest) and digest =~ ~r/\A[0-9a-f]{64}\z/)
        row |> Map.delete("map_matching_input_digest") |> track_normalize()
      end)

    expected_tracks =
      Enum.map(expected["tracks"], fn row ->
        row
        |> then(&ApiGolden.column_defaults("tracks", &1))
        |> Map.put("original_path", row["ewkb"])
        |> Map.delete("ewkb")
        |> Map.delete("map_matching_input_digest")
        |> Map.update!("dominant_mode", &Segments.mode_to_int/1)
        |> track_normalize()
      end)

    assert actual_tracks == expected_tracks

    assert Enum.map(segments, fn [row] -> track_normalize(row) end) ==
             expected["segments"] |> Enum.sort_by(& &1["id"]) |> Enum.map(&track_normalize/1)
  end

  defp track_normalize(row) do
    Map.new(row, fn
      {key, stamp}
      when key in ~w(created_at updated_at start_at end_at corrected_at) and is_binary(stamp) ->
        parsed =
          case DateTime.from_iso8601(stamp) do
            {:ok, time, _} -> time
            _ -> stamp |> NaiveDateTime.from_iso8601!() |> DateTime.from_naive!("Etc/UTC")
          end

        {key, DateTime.to_unix(parsed, :microsecond)}

      {key, geometry} when key in ~w(path original_path) and is_binary(geometry) ->
        {key, String.downcase(geometry)}

      pair ->
        pair
    end)
  end

  defp track_assert_track(expected, id) do
    track = Enum.find(expected["tracks"], &(&1["id"] == id))
    {:ok, stamp, _} = DateTime.from_iso8601(track["updated_at"])

    assert rows("SELECT dominant_mode,lock_version,updated_at FROM tracks WHERE id=$1", [id]) == [
             [
               Segments.mode_to_int(track["dominant_mode"]),
               track["lock_version"],
               DateTime.to_naive(stamp)
             ]
           ]
  end

  defp track_assert_segments(expected, id) do
    fields =
      ~w(id track_id transportation_mode source distance duration avg_speed max_speed confidence confidence_score start_index end_index)

    actual =
      rows("SELECT to_jsonb(s) FROM track_segments s WHERE track_id=$1 ORDER BY id", [id])
      |> Enum.map(fn [row] -> Map.take(row, fields) end)

    assert actual ==
             expected["segments"]
             |> Enum.filter(&(&1["track_id"] == id))
             |> Enum.map(&Map.take(&1, fields))

    for row <- expected["segments"], row["track_id"] == id do
      {:ok, created, _} = DateTime.from_iso8601(row["created_at"])
      {:ok, updated, _} = DateTime.from_iso8601(row["updated_at"])

      assert rows("SELECT created_at,updated_at FROM track_segments WHERE id=$1", [row["id"]]) ==
               [[DateTime.to_naive(created), DateTime.to_naive(updated)]]
    end
  end

  defp achievement_setup do
    start_oban(@oban)
    Registry.all()
    registry = :persistent_term.get(Registry)

    sequences =
      Map.new(~w(countries regions), &{&1, rows("SELECT last_value,is_called FROM #{&1}_id_seq")})

    keys =
      ~w(command:release.achievements_backfill command:achievements.bulk_check command:achievements.check cron:achievements_bulk_check_job)

    owners =
      rows(
        "SELECT key,owner,pinned,updated_at,updated_by FROM phoenix.job_owners WHERE key=ANY($1)",
        [keys]
      )

    on_exit(fn ->
      :persistent_term.put(Registry, registry)
      rows("DROP TRIGGER IF EXISTS a12rel_load_failure ON regions")
      rows("DROP FUNCTION IF EXISTS a12rel_load_failure()")

      for table <- ["regions", "oban.oban_jobs", "phoenix.rails_commands"] do
        rows("DROP TRIGGER IF EXISTS a12rel_boundary_failure ON #{table}")
      end

      rows("DROP FUNCTION IF EXISTS a12rel_boundary_failure()")

      if rows(
           "SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='regions' AND column_name='a12rel_missing_geom')"
         ) == [[true]] do
        rows("ALTER TABLE regions RENAME COLUMN a12rel_missing_geom TO geom")
      end

      rows("DELETE FROM regions")
      rows("DELETE FROM countries WHERE id=54001")
      rows("DELETE FROM phoenix.job_owners WHERE key=ANY($1)", [keys])

      for row <- owners do
        rows(
          "INSERT INTO phoenix.job_owners(key,owner,pinned,updated_at,updated_by) VALUES($1,$2,$3,$4,$5)",
          row
        )
      end

      for {table, [[value, called]]} <- sequences do
        rows("SELECT setval('#{table}_id_seq',$1,$2)", [value, called])
      end
    end)

    :ok
  end

  defp achievement_failures do
    fixture =
      Path.expand("../../fixtures/a12rel/achievements.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    states = Map.new(fixture["cases"], &{&1["id"], &1})
    geometry_index = fixture["geometries"] |> Enum.with_index() |> Map.new()
    achievement_country()

    for {profile, owner} <- [
          {"repair_failure", :oban},
          {"enqueue_failure", :oban},
          {"enqueue_failure", :sidekiq},
          {"load_failure", :oban}
        ] do
      rows("DELETE FROM regions")
      rows("DELETE FROM oban.oban_jobs")
      rows("DELETE FROM phoenix.rails_commands")
      rows("DELETE FROM phoenix.processed_commands WHERE event_id=$1", [Ecto.UUID.dump!(@event)])
      achievement_seed_source_regions()
      Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:achievements.bulk_check", owner)
      source = states[profile]

      assert achievement_project_regions(achievement_region_rows(), geometry_index, []) ==
               source["before"]

      achievement_install_failure(profile, owner)

      {_error, statements} =
        achievement_observe_region_statements(fn ->
          assert_raise Postgrex.Error, fn ->
            Achievements.run(ScratchRepo, @oban, @args, now: @achievement_now)
          end
        end)

      achievement_remove_failure(profile, owner)
      after_rows = achievement_region_rows()
      assert length(after_rows) == length(source["after"])
      actual = achievement_project_regions(after_rows, geometry_index, statements)
      assert actual == source["after"]
      assert achievement_committed_region_rows() == after_rows
      refute Dawarich.Jobs.Processed.done?(ScratchRepo, @event)
      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

      {result, retry_statements} =
        achievement_observe_region_statements(fn ->
          Achievements.run(ScratchRepo, @oban, @args, now: @achievement_now)
        end)

      assert result == :ok
      assert Dawarich.Jobs.Processed.done?(ScratchRepo, @event)

      if profile != "load_failure" do
        assert retry_statements == []

        assert achievement_project_regions(achievement_region_rows(), geometry_index, statements) ==
                 source["retry"]["after"]
      else
        assert Enum.map(retry_statements, & &1.kind) == ["upsert", "repair"]

        assert achievement_project_regions(
                 achievement_region_rows(),
                 geometry_index,
                 retry_statements
               ) ==
                 states["cloud"]["after"]
      end

      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[if(owner == :oban, do: 1, else: 0)]]

      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [
               [if(owner == :sidekiq, do: 1, else: 0)]
             ]
    end
  end

  defp achievement_successes do
    fixture = Path.join(@dir, "achievements.json") |> File.read!() |> Jason.decode!()
    geometry_index = fixture["geometries"] |> Enum.with_index() |> Map.new()

    for profile <- fixture["cases"], is_nil(profile["error"]) do
      rows("DELETE FROM regions")
      rows("DELETE FROM countries")
      rows("DELETE FROM oban.oban_jobs")
      rows("DELETE FROM phoenix.rails_commands")
      if profile["id"] != "countries_empty", do: achievement_country()

      for chunk <- Enum.chunk_every(profile["before"], 500) do
        values =
          Enum.map(chunk, fn row ->
            [row["id"], row["code"], Enum.at(fixture["geometries"], row["geometry"])]
          end)
          |> Enum.zip()
          |> Enum.map(&Tuple.to_list/1)

        rows(
          """
          INSERT INTO regions(id,code,geom,created_at,updated_at)
          SELECT id,code,ST_GeomFromEWKB(decode(ewkb,'hex')),'2026-01-01','2026-01-01'
          FROM unnest($1::bigint[],$2::text[],$3::text[]) AS input(id,code,ewkb)
          """,
          values
        )
      end

      rows("SELECT setval('regions_id_seq',$1,false)", [
        Enum.max(Enum.map(profile["before"], & &1["id"])) + 1
      ])

      event = Ecto.UUID.generate()
      args = Map.put(@args, "event_id", event)
      Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:achievements.bulk_check", :oban)

      {result, statements} =
        achievement_observe_region_statements(fn ->
          Achievements.run(ScratchRepo, @oban, args, now: @achievement_now)
        end)

      assert result == :ok

      assert achievement_project_regions(achievement_region_rows(), geometry_index, statements) ==
               profile["after"]

      assert achievement_committed_region_rows() == achievement_region_rows()
      jobs = rows("SELECT args,scheduled_at FROM oban.oban_jobs ORDER BY id")

      expected =
        Enum.take(profile["jobs"], 1)
        |> Enum.map(fn job ->
          [
            job["arguments"]
            |> hd()
            |> Map.put(
              "event_id",
              Dawarich.Achievements.BulkCheck.job_id(
                Dawarich.Achievements.BulkCheck.release_job_id(event)
              )
            ),
            DateTime.to_naive(@achievement_now)
          ]
        end)

      assert jobs == expected

      if profile["id"] == "repeat" do
        assert Achievements.run(ScratchRepo, @oban, args, now: @achievement_now) == :ok
        assert rows("SELECT args,scheduled_at FROM oban.oban_jobs ORDER BY id") == jobs
      end
    end
  end

  defp achievement_country do
    rows("""
    INSERT INTO countries(id,name,iso_a2,iso_a3,created_at,updated_at)
    VALUES(54001,'A12rel synthetic country','ZZ','ZZZ','2026-01-01','2026-01-01')
    """)
  end

  defp achievement_seed_source_regions do
    rows("""
    INSERT INTO regions(id,code,geom,created_at,updated_at) VALUES
    (55000,'DE-BE',#{@valid},'2026-01-01','2026-01-01'),
    (55001,'ZZ-INVALID',ST_GeomFromText('MULTIPOLYGON(((0 0,2 2,2 0,0 2,0 0)))',4326),'2026-01-01','2026-01-01'),
    (55002,'ZZ-SENTINEL',#{@valid},'2026-01-01','2026-01-01')
    """)

    rows("SELECT setval('regions_id_seq',55003,false)")
  end

  defp achievement_install_failure("load_failure", _owner),
    do: rows("ALTER TABLE regions RENAME COLUMN geom TO a12rel_missing_geom")

  defp achievement_install_failure(profile, owner) do
    {table, event, body} =
      case {profile, owner} do
        {"repair_failure", _} ->
          {"regions", "UPDATE OF geom",
           "IF NEW.updated_at=OLD.updated_at THEN RAISE EXCEPTION 'A12rel repair failure'; END IF; RETURN NEW;"}

        {"enqueue_failure", :oban} ->
          {"oban.oban_jobs", "INSERT", "RAISE EXCEPTION 'A12rel publication failure';"}

        {"enqueue_failure", :sidekiq} ->
          {"phoenix.rails_commands", "INSERT", "RAISE EXCEPTION 'A12rel publication failure';"}
      end

    rows(
      "CREATE FUNCTION a12rel_boundary_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN #{body} END $$"
    )

    rows(
      "CREATE TRIGGER a12rel_boundary_failure BEFORE #{event} ON #{table} FOR EACH ROW EXECUTE FUNCTION a12rel_boundary_failure()"
    )
  end

  defp achievement_remove_failure("load_failure", _owner),
    do: rows("ALTER TABLE regions RENAME COLUMN a12rel_missing_geom TO geom")

  defp achievement_remove_failure(profile, owner) do
    table =
      case {profile, owner} do
        {"repair_failure", _} -> "regions"
        {_, :oban} -> "oban.oban_jobs"
        {_, :sidekiq} -> "phoenix.rails_commands"
      end

    rows("DROP TRIGGER a12rel_boundary_failure ON #{table}")
    rows("DROP FUNCTION a12rel_boundary_failure()")
  end

  defp achievement_region_rows do
    rows(
      "SELECT id,code,encode(ST_AsEWKB(geom),'hex'),ST_IsValid(geom),created_at,updated_at FROM regions ORDER BY id"
    )
  end

  defp achievement_clock do
    [[stamp]] = rows("SELECT clock_timestamp() AT TIME ZONE 'UTC'")
    stamp
  end

  defp achievement_observe_region_statements(work) do
    id = {__MODULE__, make_ref()}
    key = {__MODULE__, :region_statements}
    Process.put(key, %{lower: achievement_clock(), statements: []})

    :ok =
      :telemetry.attach(
        id,
        [:dawarich, :scratch_repo, :query],
        fn _event, _measurements, metadata, caller ->
          if self() == caller, do: achievement_capture_region_statement(metadata, key)
        end,
        self()
      )

    try do
      result = work.()
      {result, Process.get(key).statements}
    after
      :telemetry.detach(id)
      Process.delete(key)
    end
  end

  defp achievement_capture_region_statement(%{query: sql, result: {:ok, _}}, key) do
    kind =
      cond do
        sql == "SELECT EXISTS (SELECT 1 FROM countries)" -> "countries"
        String.starts_with?(sql, "INSERT INTO regions (code, geom,") -> "upsert"
        String.starts_with?(sql, "UPDATE regions\nSET geom") -> "repair"
        true -> nil
      end

    if kind do
      state = Process.get(key)
      upper = achievement_clock()

      statements =
        if kind == "countries" do
          state.statements
        else
          achievement_snapshot = achievement_region_rows()

          if kind == "repair" do
            upsert = List.last(state.statements)

            assert Enum.map(achievement_snapshot, &Enum.drop(&1, 4)) ==
                     Enum.map(upsert.rows, &Enum.drop(&1, 4))
          end

          state.statements ++
            [%{kind: kind, lower: state.lower, upper: upper, rows: achievement_snapshot}]
        end

      Process.put(key, %{lower: achievement_clock(), statements: statements})
    end
  end

  defp achievement_capture_region_statement(_metadata, _key), do: :ok

  defp achievement_project_regions(data, geometries, statements) do
    for [id, code, ewkb, valid, created, updated] <- data do
      %{
        "id" => id,
        "code" => code,
        "geometry" => Map.fetch!(geometries, ewkb),
        "valid" => valid,
        "created_at" => achievement_project_region_timestamp(created, statements),
        "updated_at" => achievement_project_region_timestamp(updated, statements)
      }
    end
  end

  defp achievement_project_region_timestamp(~N[2026-01-01 00:00:00.000000], _statements),
    do: "2026-01-01T00:00:00.000000Z"

  defp achievement_project_region_timestamp(stamp, statements) do
    upsert = Enum.find(statements, &(&1.kind == "upsert"))
    assert upsert
    assert NaiveDateTime.compare(stamp, upsert.lower) in [:eq, :gt]
    assert NaiveDateTime.compare(stamp, upsert.upper) in [:eq, :lt]
    %{"database_now" => "upsert", "bounded" => true}
  end

  defp achievement_committed_region_rows do
    ScratchRepo.checkout(fn ->
      [[first]] = rows("SELECT pg_backend_pid()")

      {second, data} =
        Task.async(fn ->
          ScratchRepo.checkout(fn ->
            [[pid]] = rows("SELECT pg_backend_pid()")
            {pid, achievement_region_rows()}
          end)
        end)
        |> Task.await()

      assert first != second
      data
    end)
  end

  @tag :rails_parity
  @tag :a12rel_reverse_handoff
  test "publishes actual A12rel reverse rows for Rails acceptance" do
    start_oban(@oban)
    schema_hash = :crypto.hash(:sha, File.read!("../db/schema.rb")) |> Base.encode16(case: :lower)

    for {key, value} <- [{"environment", "test"}, {"schema_sha1", schema_hash}] do
      rows(
        "INSERT INTO ar_internal_metadata(key,value,created_at,updated_at) VALUES($1,$2,now(),now()) ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value",
        [key, value]
      )
    end

    achievement_country()
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:achievements.bulk_check", :sidekiq)
    assert Achievements.run(ScratchRepo, @oban, @args, now: @achievement_now) == :ok
    [[kind, payload]] = rows("SELECT kind,payload FROM phoenix.rails_commands")
    assert kind == "release_achievements_bulk_check"

    assert payload == %{
             "job_id" => "2ce791c6-a6d3-57d0-a80b-f180c7944093",
             "options" => %{"notify" => false, "force" => true, "stale_only" => true},
             "run_at" => DateTime.to_iso8601(@achievement_now)
           }

    for id <- [54_901, 54_902] do
      rows(
        "INSERT INTO users(id,email,status,created_at,updated_at) VALUES($1,$2,1,now(),now())",
        [id, "a12rel-handoff-#{id}@example.invalid"]
      )

      rows(
        "INSERT INTO points(id,user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$1,1780300000,ST_SetSRID(ST_MakePoint(13,52),4326),now(),now())",
        [id]
      )
    end

    root = "00000000-0000-4000-8000-000000549001"
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:achievements.check", :sidekiq)

    assert Dawarich.Achievements.BulkCheck.run(
             ScratchRepo,
             @oban,
             %{"event_id" => root, "notify" => false, "force" => true, "stale_only" => true},
             now: @achievement_now
           ) == :ok

    assert rows(
             "SELECT payload FROM phoenix.rails_commands WHERE kind='achievements.bulk_check_leaf' ORDER BY id"
           ) ==
             Enum.map([54_901, 54_902], fn id ->
               [
                 %{
                   "user_id" => id,
                   "notify" => false,
                   "run_at" => DateTime.to_iso8601(@achievement_now),
                   "force" => true,
                   "event_id" => Dawarich.Achievements.BulkCheck.child_id(root, id)
                 }
               ]
             end)

    Dawarich.Jobs.Ownership.put!(ScratchRepo, "cron:achievements_bulk_check_job", :oban,
      pinned: true
    )
  end
end
