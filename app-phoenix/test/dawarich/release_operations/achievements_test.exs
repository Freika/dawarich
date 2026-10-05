defmodule Dawarich.ReleaseOperations.AchievementsTest do
  use Dawarich.JobsCase

  alias Dawarich.Achievements.Registry
  alias Dawarich.ReleaseOperations.Achievements

  @oban __MODULE__.Oban
  @event "00000000-0000-4000-8000-000000540001"
  @now ~U[2026-10-04 12:00:00.000000Z]
  @args %{"version" => 1, "event_id" => @event}
  @valid "ST_Multi(ST_GeomFromText('POLYGON((0 0,1 0,1 1,0 1,0 0))',4326))"

  setup do
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

  test "region partial writes survive enqueue failure while publication remains retryable" do
    fixture =
      Path.expand("../../fixtures/a12rel/achievements.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    states = Map.new(fixture["cases"], &{&1["id"], &1})
    geometry_index = fixture["geometries"] |> Enum.with_index() |> Map.new()
    country()

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
      seed_source_regions()
      Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:achievements.bulk_check", owner)
      source = states[profile]
      assert project_regions(region_rows(), geometry_index, []) == source["before"]
      install_failure(profile, owner)

      {_error, statements} =
        observe_region_statements(fn ->
          assert_raise Postgrex.Error, fn ->
            Achievements.run(ScratchRepo, @oban, @args, now: @now)
          end
        end)

      remove_failure(profile, owner)
      after_rows = region_rows()
      assert length(after_rows) == length(source["after"])
      actual = project_regions(after_rows, geometry_index, statements)
      assert actual == source["after"]
      assert committed_region_rows() == after_rows
      refute Dawarich.Jobs.Processed.done?(ScratchRepo, @event)
      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

      {result, retry_statements} =
        observe_region_statements(fn ->
          Achievements.run(ScratchRepo, @oban, @args, now: @now)
        end)

      assert result == :ok
      assert Dawarich.Jobs.Processed.done?(ScratchRepo, @event)

      if profile != "load_failure" do
        assert retry_statements == []

        assert project_regions(region_rows(), geometry_index, statements) ==
                 source["retry"]["after"]
      else
        assert Enum.map(retry_statements, & &1.kind) == ["upsert", "repair"]

        assert project_regions(region_rows(), geometry_index, retry_statements) ==
                 states["cloud"]["after"]
      end

      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[if(owner == :oban, do: 1, else: 0)]]

      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [
               [if(owner == :sidekiq, do: 1, else: 0)]
             ]
    end
  end

  test "release achievements waits for countries and loads only missing registry codes" do
    definitions = Registry.all()

    expected =
      definitions
      |> Enum.filter(&(&1.level == "subdivision"))
      |> Enum.flat_map(& &1.region_codes)
      |> MapSet.new()

    assert Registry.subdivision_codes() == expected
    seed_regions(["ZZ-SENTINEL"])
    before = snapshot()
    assert run() == :ok
    assert snapshot() == before

    country()
    rows("DELETE FROM regions")
    codes = MapSet.to_list(expected) |> Enum.sort()
    seed_regions(codes)
    before = snapshot()
    assert run() == :ok
    assert snapshot() == before

    rows("DELETE FROM regions")
    seed_regions(Enum.map(1..length(codes), &"ZZ-#{&1}"))
    assert rows("SELECT count(*) FROM regions") == [[length(codes)]]
    assert run() == :ok
    assert required_count(codes) == length(codes)
    assert rows("SELECT count(*) FROM regions WHERE NOT ST_IsValid(geom)") == [[0]]

    for host <- ["cloud", "self_hosted", "legacy_disabled"] do
      rows("DELETE FROM regions")
      assert run(host: host) == :ok
      assert required_count(codes) == length(codes)
    end

    original = :persistent_term.get(Registry)
    definition = Enum.find(definitions, &(&1.level == "subdivision"))

    :persistent_term.put(Registry, %{
      original
      | definitions: [
          %{definition | kind: "continent", region_codes: ["DE-BE", "DE-BY"]},
          %{definition | region_codes: ["DE-BY"]},
          %{definition | level: "country", region_codes: ["US"]}
        ]
    })

    assert Registry.subdivision_codes() == MapSet.new(["DE-BE", "DE-BY"])
    :persistent_term.put(Registry, %{original | definitions: []})
    rows("DELETE FROM regions")
    assert run() == :ok
    assert snapshot() == []

    :persistent_term.put(Registry, original)

    rows("""
    CREATE FUNCTION a12rel_load_failure() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN RAISE EXCEPTION 'A12rel upsert failure'; END $$
    """)

    rows("""
    CREATE TRIGGER a12rel_load_failure BEFORE INSERT ON regions
    FOR EACH ROW EXECUTE FUNCTION a12rel_load_failure()
    """)

    assert_raise Postgrex.Error, ~r/A12rel upsert failure/, fn -> run() end
    assert snapshot() == []
  end

  test "release bulk reverse insertion accepts only the validated fleet payload" do
    payload = %{
      "job_id" => @event,
      "options" => %{"notify" => false, "force" => true, "stale_only" => true},
      "run_at" => DateTime.to_iso8601(@now)
    }

    assert Dawarich.RailsCommands.insert!(ScratchRepo, "release_achievements_bulk_check", payload) ==
             :ok

    assert rows("SELECT kind,payload FROM phoenix.rails_commands") == [
             ["release_achievements_bulk_check", payload]
           ]

    invalid =
      Enum.map(Map.keys(payload), &Map.delete(payload, &1)) ++
        [
          Map.put(payload, "extra", 1),
          Map.put(payload, "user_id", 54001),
          Map.put(payload, "job_id", "invalid"),
          Map.put(payload, "job_id", nil),
          Map.put(payload, "run_at", "invalid"),
          Map.put(payload, "run_at", "2026-10-04T12:00:00"),
          Map.put(payload, "options", %{}),
          put_in(payload, ["options", "notify"], "false"),
          put_in(payload, ["options", "force"], 1),
          put_in(payload, ["options", "stale_only"], nil),
          put_in(payload, ["options", "extra"], false)
        ]

    for bad <- invalid do
      assert_raise ArgumentError, fn ->
        Dawarich.RailsCommands.insert!(ScratchRepo, "release_achievements_bulk_check", bad)
      end
    end

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[1]]
  end

  test "release parent publishes silent stale bulk after regions to its command owner" do
    country()
    codes = Registry.subdivision_codes() |> MapSet.to_list()
    options = %{"notify" => false, "force" => true, "stale_only" => true}
    job_id = "2ce791c6-a6d3-57d0-a80b-f180c7944093"
    root = "e18e8b6f-370a-5f22-a306-3291938cd8c5"

    for owner <- [:oban, :sidekiq] do
      opposite = if owner == :oban, do: :sidekiq, else: :oban
      Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:release.achievements_backfill", :sidekiq)
      Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:achievements.bulk_check", owner)
      Dawarich.Jobs.Ownership.put!(ScratchRepo, "cron:achievements_bulk_check_job", opposite)
      Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:achievements.check", opposite)

      assert Achievements.run(ScratchRepo, @oban, @args, now: @now) == :ok
      assert required_count(codes) == length(codes)
      assert Dawarich.Jobs.Processed.done?(ScratchRepo, @event)
      refute Dawarich.Jobs.Processed.done?(ScratchRepo, root)

      if owner == :oban do
        assert rows("SELECT worker,args,scheduled_at FROM oban.oban_jobs") == [
                 [
                   "Dawarich.Achievements.BulkCheckWorker",
                   Map.put(options, "event_id", root),
                   DateTime.to_naive(@now)
                 ]
               ]

        assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

        assert {:ok, ^options} =
                 Dawarich.Achievements.BulkCheckWorker.args_from_command(1, options)
      else
        assert rows("SELECT kind,payload FROM phoenix.rails_commands") == [
                 [
                   "release_achievements_bulk_check",
                   %{
                     "job_id" => job_id,
                     "options" => options,
                     "run_at" => DateTime.to_iso8601(@now)
                   }
                 ]
               ]

        assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
      end

      assert Achievements.run(ScratchRepo, @oban, @args, now: @now) == :ok
      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[if(owner == :oban, do: 1, else: 0)]]

      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [
               [if(owner == :sidekiq, do: 1, else: 0)]
             ]

      rows("DELETE FROM oban.oban_jobs")
      rows("DELETE FROM phoenix.rails_commands")
      rows("DELETE FROM phoenix.processed_commands WHERE event_id=$1", [Ecto.UUID.dump!(@event)])
    end
  end

  defp run(opts \\ []) do
    args = Map.put(@args, "event_id", Ecto.UUID.generate())
    Achievements.run(ScratchRepo, @oban, args, [now: @now] ++ opts)
  end

  defp country do
    rows("""
    INSERT INTO countries(id,name,iso_a2,iso_a3,created_at,updated_at)
    VALUES(54001,'A12rel synthetic country','ZZ','ZZZ','2026-01-01','2026-01-01')
    """)
  end

  defp seed_regions(codes) do
    rows(
      """
      INSERT INTO regions(code,geom,created_at,updated_at)
      SELECT code, #{@valid}, '2026-01-01', '2026-01-01' FROM unnest($1::varchar[]) code
      """,
      [codes]
    )
  end

  defp required_count(codes) do
    [[count]] = rows("SELECT count(*) FROM regions WHERE code = ANY($1::varchar[])", [codes])
    count
  end

  defp snapshot do
    rows("SELECT id,code,ST_AsEWKB(geom),created_at,updated_at FROM regions ORDER BY id")
  end

  defp seed_source_regions do
    rows("""
    INSERT INTO regions(id,code,geom,created_at,updated_at) VALUES
    (55000,'DE-BE',#{@valid},'2026-01-01','2026-01-01'),
    (55001,'ZZ-INVALID',ST_GeomFromText('MULTIPOLYGON(((0 0,2 2,2 0,0 2,0 0)))',4326),'2026-01-01','2026-01-01'),
    (55002,'ZZ-SENTINEL',#{@valid},'2026-01-01','2026-01-01')
    """)

    rows("SELECT setval('regions_id_seq',55003,false)")
  end

  defp install_failure("load_failure", _owner),
    do: rows("ALTER TABLE regions RENAME COLUMN geom TO a12rel_missing_geom")

  defp install_failure(profile, owner) do
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

  defp remove_failure("load_failure", _owner),
    do: rows("ALTER TABLE regions RENAME COLUMN a12rel_missing_geom TO geom")

  defp remove_failure(profile, owner) do
    table =
      case {profile, owner} do
        {"repair_failure", _} -> "regions"
        {_, :oban} -> "oban.oban_jobs"
        {_, :sidekiq} -> "phoenix.rails_commands"
      end

    rows("DROP TRIGGER a12rel_boundary_failure ON #{table}")
    rows("DROP FUNCTION a12rel_boundary_failure()")
  end

  defp region_rows do
    rows(
      "SELECT id,code,encode(ST_AsEWKB(geom),'hex'),ST_IsValid(geom),created_at,updated_at FROM regions ORDER BY id"
    )
  end

  defp clock do
    [[stamp]] = rows("SELECT clock_timestamp() AT TIME ZONE 'UTC'")
    stamp
  end

  defp observe_region_statements(work) do
    id = {__MODULE__, make_ref()}
    key = {__MODULE__, :region_statements}
    Process.put(key, %{lower: clock(), statements: []})

    :ok =
      :telemetry.attach(
        id,
        [:dawarich, :scratch_repo, :query],
        fn _event, _measurements, metadata, caller ->
          if self() == caller, do: capture_region_statement(metadata, key)
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

  defp capture_region_statement(%{query: sql, result: {:ok, _}}, key) do
    kind =
      cond do
        sql == "SELECT EXISTS (SELECT 1 FROM countries)" -> "countries"
        String.starts_with?(sql, "INSERT INTO regions (code, geom,") -> "upsert"
        String.starts_with?(sql, "UPDATE regions\nSET geom") -> "repair"
        true -> nil
      end

    if kind do
      state = Process.get(key)
      upper = clock()

      statements =
        if kind == "countries" do
          state.statements
        else
          snapshot = region_rows()

          if kind == "repair" do
            upsert = List.last(state.statements)

            assert Enum.map(snapshot, &Enum.drop(&1, 4)) ==
                     Enum.map(upsert.rows, &Enum.drop(&1, 4))
          end

          state.statements ++ [%{kind: kind, lower: state.lower, upper: upper, rows: snapshot}]
        end

      Process.put(key, %{lower: clock(), statements: statements})
    end
  end

  defp capture_region_statement(_metadata, _key), do: :ok

  defp project_regions(data, geometries, statements) do
    for [id, code, ewkb, valid, created, updated] <- data do
      %{
        "id" => id,
        "code" => code,
        "geometry" => Map.fetch!(geometries, ewkb),
        "valid" => valid,
        "created_at" => project_region_timestamp(created, statements),
        "updated_at" => project_region_timestamp(updated, statements)
      }
    end
  end

  defp project_region_timestamp(~N[2026-01-01 00:00:00.000000], _statements),
    do: "2026-01-01T00:00:00.000000Z"

  defp project_region_timestamp(stamp, statements) do
    upsert = Enum.find(statements, &(&1.kind == "upsert"))
    assert upsert
    assert NaiveDateTime.compare(stamp, upsert.lower) in [:eq, :gt]
    assert NaiveDateTime.compare(stamp, upsert.upper) in [:eq, :lt]
    %{"database_now" => "upsert", "bounded" => true}
  end

  defp committed_region_rows do
    ScratchRepo.checkout(fn ->
      [[first]] = rows("SELECT pg_backend_pid()")

      {second, data} =
        Task.async(fn ->
          ScratchRepo.checkout(fn ->
            [[pid]] = rows("SELECT pg_backend_pid()")
            {pid, region_rows()}
          end)
        end)
        |> Task.await()

      assert first != second
      data
    end)
  end
end
