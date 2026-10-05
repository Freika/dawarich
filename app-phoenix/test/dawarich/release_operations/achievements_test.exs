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

    on_exit(fn ->
      :persistent_term.put(Registry, registry)
      rows("DROP TRIGGER IF EXISTS a12rel_load_failure ON regions")
      rows("DROP FUNCTION IF EXISTS a12rel_load_failure()")
    end)

    :ok
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
end
