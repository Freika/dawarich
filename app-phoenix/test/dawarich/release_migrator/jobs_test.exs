defmodule Dawarich.ReleaseMigrator.JobsTest.Release do
  @behaviour Dawarich.ReleaseMigration

  def release, do: "9.9.9"
  def data_versions, do: []

  def steps do
    [{"20991201000001", &apply/1}]
  end

  def apply(repo) do
    repo.query!("INSERT INTO effects (name) VALUES ('applied')", [], log: false)

    jobs = repo.query!("SELECT class, args, wait FROM vectors ORDER BY id", [], log: false).rows
    {:jobs, Enum.map(jobs, fn [class, args, wait] -> {class, args, wait} end)}
  end
end

defmodule Dawarich.ReleaseMigrator.JobsTest.Outside do
  @behaviour Dawarich.ReleaseMigration

  def release, do: "9.9.9"
  def data_versions, do: []

  def steps do
    [
      {"20991201000001",
       fn repo ->
         repo.query!("INSERT INTO effects (name) VALUES ('partial')")
         repo.query!("SELECT * FROM a12h_missing_table")
         {:jobs, [{"DataMigrations::FixRouteOpacityJob", [], 0}]}
       end, transaction: false}
    ]
  end
end

defmodule Dawarich.ReleaseMigrator.JobsTest.Gated do
  @behaviour Dawarich.ReleaseMigration

  def release, do: "9.9.9"
  def data_versions, do: []

  def steps do
    [
      {"20991201000001",
       fn repo ->
         [[owner]] = repo.query!("SELECT owner FROM gate").rows
         send(:erlang.binary_to_term(owner), {:inside, self()})

         receive do
           :finish -> Dawarich.ReleaseMigrator.JobsTest.Release.apply(repo)
         end
       end}
    ]
  end
end

defmodule Dawarich.ReleaseMigrator.JobsTest do
  use Dawarich.ScratchCase

  alias Dawarich.ReleaseMigrator
  alias Dawarich.ReleaseMigrator.Floor
  alias Dawarich.ReleaseMigrator.JobsTest.{Gated, Outside, Release}
  alias Dawarich.ReleaseOperations.{AddPointDimensions, TracksDedup}

  setup do
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(oban.oban_jobs))

    scratch_sql!("""
    CREATE TABLE schema_migrations (version text PRIMARY KEY);
    CREATE TABLE effects (name text);
    CREATE TABLE vectors (id bigserial PRIMARY KEY, class text, args jsonb, wait integer);
    """)

    ScratchRepo.query!("INSERT INTO schema_migrations SELECT unnest($1::text[])", [
      Floor.versions()
    ])

    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")

      scratch_sql!("ALTER TABLE oban.oban_jobs DROP CONSTRAINT IF EXISTS a12h_insert_failure")
    end)

    :ok
  end

  test "live record commits native jobs and ledger together with original delay and worker options" do
    vector("DataMigrations::AddPointDimensionColumnsJob", [], 120)
    vector("Tracks::DeduplicationJob", [12], 130)
    before = NaiveDateTime.utc_now()
    assert {:ok, %{applied: ["20991201000001"]}} = migrate()
    after_run = NaiveDateTime.utc_now()
    assert ledger() == ["20991201000001"]
    assert effects() == [["applied"]]
    assert length(intents()) == 2

    assert [
             [worker1, args1, "maintenance", 3, 288, schedule1],
             [worker2, args2, "maintenance", 3, 10, schedule2]
           ] = jobs()

    assert worker1 == Oban.Worker.to_string(AddPointDimensions)
    assert worker2 == Oban.Worker.to_string(TracksDedup)
    assert args1 == %{"version" => 1}
    assert args2 == %{"version" => 1, "user_id" => 12}

    for {time, wait} <- [{schedule1, 120}, {schedule2, 130}] do
      assert NaiveDateTime.compare(time, NaiveDateTime.add(before, wait)) in [:gt, :eq]
      assert NaiveDateTime.compare(time, NaiveDateTime.add(after_run, wait)) in [:lt, :eq]
    end
  end

  test "insert failure rolls back effects ledger and intents" do
    vector("DataMigrations::FixRouteOpacityJob", [], 0)

    scratch_sql!("""
    ALTER TABLE oban.oban_jobs ADD CONSTRAINT a12h_insert_failure
    CHECK (worker <> 'Dawarich.ReleaseOperations.RouteOpacity')
    """)

    assert {:error, {:failed, "9.9.9", "20991201000001", banner}} = migrate()
    assert banner =~ "a12h_insert_failure"
    assert effects() == []
    assert ledger() == []
    assert intents() == []
    assert jobs() == []
  end

  @tag a12f3b_case: "E192b"
  test "skip records intent without job and invalid decodes refuse the version" do
    vector("DataMigrations::BackfillFamiliesForFamilyPlanJob", [], 0)
    assert {:ok, _} = migrate()
    assert [["DataMigrations::BackfillFamiliesForFamilyPlanJob", [], 0]] = intents()
    assert jobs() == []

    for {class, args} <- [
          {"DataMigrations::BackfillAchievementsJob", [1]},
          {"TransportationModes::ImportBackfillJob", [nil]},
          {"DataMigrations::FixRouteOpacityJob", [1]},
          {"DataMigrations::SetPointsCountryIdsJob", [42]},
          {"DataMigrations::SetReverseGeocodedAtForPointsJob", []},
          {"DataMigrations::StartSettingsPointsCountryIdsJob", []},
          {"UnknownJob", []}
        ] do
      scratch_sql!(
        "DELETE FROM schema_migrations WHERE version >= '2099'; DELETE FROM effects; DELETE FROM vectors; DELETE FROM phoenix.release_migration_jobs;"
      )

      vector(class, args, 0)
      assert {:error, {:failed, "9.9.9", "20991201000001", banner}} = migrate()
      assert banner =~ "release job"
      assert effects() == []
      assert ledger() == []
      assert intents() == []
      assert jobs() == []
    end
  end

  test "second live migrate does not replay prior intents" do
    vector("DataMigrations::RecalculateAnomaliesJob", [], 20)

    ScratchRepo.query!(
      "INSERT INTO phoenix.release_migration_jobs (version,job_class,arguments,wait_seconds) VALUES ('old-proof','UnknownJob','[]',0)"
    )

    assert {:ok, _} = migrate()

    original_jobs =
      ScratchRepo.query!("SELECT id,args,state,scheduled_at FROM oban.oban_jobs ORDER BY id").rows

    original_intents = intents()
    assert length(original_jobs) == 1
    assert {:ok, %{applied: []}} = migrate()

    assert ScratchRepo.query!("SELECT id,args,state,scheduled_at FROM oban.oban_jobs ORDER BY id").rows ==
             original_jobs

    assert intents() == original_intents
    assert effects() == [["applied"]]
  end

  test "nontransactional failure leaves source effects but records no ledger or jobs" do
    assert {:error, {:failed, "9.9.9", "20991201000001", banner}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [Outside], job_mode: :enqueue)

    assert banner =~ "a12h_missing_table"
    assert effects() == [["partial"]]
    assert ledger() == []
    assert intents() == []
    assert jobs() == []
  end

  test "concurrent live migrators commit one ledger version and its exact job count" do
    vector("DataMigrations::FixRouteOpacityJob", [], 10)
    scratch_sql!("CREATE TABLE gate (owner bytea)")
    ScratchRepo.query!("INSERT INTO gate VALUES ($1)", [:erlang.term_to_binary(self())])
    parent = self()

    first =
      Task.async(fn ->
        ReleaseMigrator.migrate(ScratchRepo, releases: [Gated], job_mode: :enqueue)
      end)

    assert_receive {:inside, first_pid}, 5_000

    pause = fn _ms ->
      send(parent, {:waiting, self()})

      receive do
        :wake -> :ok
      end
    end

    second =
      Task.async(fn ->
        ReleaseMigrator.migrate(ScratchRepo,
          releases: [Gated],
          job_mode: :enqueue,
          lease_sleep: pause
        )
      end)

    assert_receive {:waiting, poller}, 5_000
    assert poller == second.pid
    refute_received {:inside, _}
    send(first_pid, :finish)
    assert {:ok, %{applied: ["20991201000001"]}} = Task.await(first)
    send(poller, :wake)
    assert {:ok, %{applied: []}} = Task.await(second)
    assert ledger() == ["20991201000001"]
    assert effects() == [["applied"]]
    assert length(intents()) == 1
    assert length(jobs()) == 1
  end

  defp migrate, do: ReleaseMigrator.migrate(ScratchRepo, releases: [Release], job_mode: :enqueue)

  defp vector(class, args, wait) do
    ScratchRepo.query!("INSERT INTO vectors (class,args,wait) VALUES ($1,$2,$3)", [
      class,
      args,
      wait
    ])
  end

  defp ledger do
    ScratchRepo.query!(
      "SELECT version FROM schema_migrations WHERE version >= '2099' ORDER BY version"
    ).rows
    |> List.flatten()
  end

  defp effects, do: ScratchRepo.query!("SELECT name FROM effects").rows

  defp intents,
    do:
      ScratchRepo.query!(
        "SELECT job_class,arguments,wait_seconds FROM phoenix.release_migration_jobs ORDER BY id"
      ).rows

  defp jobs,
    do:
      ScratchRepo.query!(
        "SELECT worker,args,queue,priority,max_attempts,scheduled_at FROM oban.oban_jobs ORDER BY id"
      ).rows
end
