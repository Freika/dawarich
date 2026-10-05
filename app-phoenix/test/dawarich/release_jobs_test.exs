defmodule Dawarich.ReleaseJobsTest do
  use Dawarich.JobsCase

  alias Dawarich.ReleaseJobs
  alias Dawarich.ReleaseOperations, as: Ops

  @app Path.expand("../..", __DIR__)
  @keywords %{"repair_collisions" => true, "_aj_ruby2_keywords" => ["repair_collisions"]}
  @v1 %{"version" => 1}
  @arg_keys ~w(version operation_id cursor user_id event_id import_id ambient_zone)
  @command_payloads %{
    "DataMigrations::AddPointDimensionColumnsJob" => %{},
    "DataMigrations::DropLegacyLatLonJob" => %{},
    "DataMigrations::BackfillAchievementsJob" => %{},
    "TransportationModes::ImportBackfillJob" => %{"import_id" => 42},
    "DataMigrations::BackfillPointDimensionsJob" => %{
      "phase" => "dimensions",
      "start_id" => nil,
      "batch_size" => 50_000,
      "repair_collisions" => false
    },
    "DataMigrations::FixRouteOpacityJob" => %{},
    "DataMigrations::BackfillOnboardingCompletedJob" => %{},
    "DataMigrations::DestroyOrphanedTracksJob" => %{},
    "DataMigrations::BackfillPlaceNameLocksJob" => %{},
    "Tracks::DeduplicationJob" => %{"user_id" => 42},
    "TrackSegments::TimeAnchorBackfillJob" => %{"from_id" => 0},
    "DataMigrations::BackfillTransportationModesJob" => %{
      "scope" => "missing",
      "from_track_id" => 0
    },
    "Visits::FleetRedetectJob" => %{},
    "DataMigrations::CleanupNullIslandJob" => %{"user_id" => nil},
    "DataMigrations::BackfillMotionDataJob" => %{"batch_size" => 1_000},
    "DataMigrations::BackfillAltitudeJob" => %{}
  }
  @country_payloads [
    {[],
     %{
       "phase" => "country",
       "start_id" => nil,
       "batch_size" => 50_000,
       "repair_collisions" => false
     }},
    {[nil, 50_000, @keywords],
     %{
       "phase" => "country",
       "start_id" => nil,
       "batch_size" => 50_000,
       "repair_collisions" => true
     }}
  ]
  @fixed_strings ~w(dimensions country users missing)

  test "A12h DDL vectors decode to executable workers and reject extras" do
    for {class, worker} <- [
          {"DataMigrations::AddPointDimensionColumnsJob", Ops.AddPointDimensions},
          {"DataMigrations::DropLegacyLatLonJob", Ops.DropLegacyCoordinates}
        ] do
      assert class in ReleaseJobs.classes()
      assert ReleaseJobs.decode(class, []) == {:ok, worker, @v1}
      assert worker.args_from_command(1, %{}) == {:ok, @v1}
      assert worker.new(@v1).valid?
      assert Ecto.Changeset.get_field(worker.new(@v1), :max_attempts) == 288
      assert worker.backoff(%Oban.Job{attempt: 2}) == 300

      for extras <- [[1], [%{}], [nil]] do
        assert ReleaseJobs.decode(class, extras) == {:error, :invalid_arguments}
      end
    end
  end

  test "achievement and import release vectors decode to executable adapters" do
    start_oban(:a12rel_vectors)
    ledger = rows("SELECT * FROM phoenix.release_migration_jobs ORDER BY id")

    for {class, arguments, worker} <- [
          {"DataMigrations::BackfillAchievementsJob", [], Ops.Achievements},
          {"TransportationModes::ImportBackfillJob", [54001], Ops.ImportBackfill}
        ] do
      assert {:ok, ^worker, args} = ReleaseJobs.decode(class, arguments)
      assert {:ok, _} = Ecto.UUID.cast(args["event_id"])
      assert worker.new(args).valid?
      assert {:ok, ^worker, other} = ReleaseJobs.decode(class, arguments)
      refute other["event_id"] == args["event_id"]

      if worker == Ops.ImportBackfill do
        assert args["import_id"] == 54001

        assert args["ambient_zone"] ==
                 Dawarich.TimeZoneName.to_iana(System.get_env("TIME_ZONE", "Europe/Berlin"))
      end
    end

    vectors =
      for name <- ~w(release_vectors import_release_vectors),
          vector <-
            File.read!(Path.join(@app, "test/fixtures/a12rel/#{name}.json"))
            |> Jason.decode!()
            |> Map.fetch!("vectors"),
          job <- vector["jobs"],
          job["class"] in ~w(DataMigrations::BackfillAchievementsJob TransportationModes::ImportBackfillJob),
          do: job

    for vector <- vectors do
      assert {:ok, worker, args} = ReleaseJobs.decode(vector["class"], vector["arguments"])
      payload = Map.drop(args, ["event_id", "version"])
      assert {:ok, decoded} = worker.args_from_command(1, payload)
      assert decoded == Map.delete(args, "event_id")
      before = DateTime.utc_now()
      changeset = worker.new(args, schedule_in: trunc(vector["due_offset"]))
      assert changeset.valid?
      job = Oban.insert!(:a12rel_vectors, changeset)
      assert job.args == args
      assert job.worker == to_string(worker) |> String.trim_leading("Elixir.")
      assert job.queue == "maintenance"
      assert job.priority == 3
      assert job.max_attempts == 26
      assert abs(DateTime.diff(job.scheduled_at, before) - vector["due_offset"]) <= 1
    end

    assert rows("SELECT * FROM phoenix.release_migration_jobs ORDER BY id") == ledger
  end

  test "keeps executable anomaly and tracker classes enumerated with invalid-argument errors" do
    start_oban(:release_recalculation_classes)

    Dawarich.RecalculationFixtures.load!(
      ScratchRepo,
      Dawarich.RecalculationFixtures.case!("tracker_stagger")
    )

    for class <-
          ~w(DataMigrations::RecalculateAnomaliesJob DataMigrations::RecalculatePerTrackerTracksJob) do
      assert class in ReleaseJobs.classes()
      assert {:ok, worker, args} = ReleaseJobs.decode(class, [])

      assert :ok =
               Ops.run(ScratchRepo, :release_recalculation_classes, worker, %Oban.Job{args: args})

      assert ReleaseJobs.decode(class, [1]) == {:error, :invalid_arguments}
      assert ReleaseJobs.decode(class, [%{"limit" => 2}]) == {:error, :invalid_arguments}
    end

    assert rows("SELECT count(*) FROM phoenix.release_operations WHERE status='completed'") == [
             [2]
           ]

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[2]]
  end

  setup do
    previous = System.get_env("SELF_HOSTED")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)
  end

  defp recorded_vectors do
    @app
    |> Path.join("lib/dawarich/release_migrations/**/*.ex")
    |> Path.wildcard()
    |> Enum.flat_map(&job_calls/1)
    |> Enum.uniq()
  end

  defp job_calls(file) do
    {_ast, calls} =
      file
      |> File.read!()
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:job, _, [class | rest]} = call, acc when is_binary(class) ->
          {call, [{class, literal(List.first(rest, []))} | acc]}

        node, acc ->
          {node, acc}
      end)

    calls
  end

  defp literal(ast) do
    ast
    |> Macro.prewalk(fn
      {name, _, context} when is_atom(name) and is_atom(context) -> 42
      node -> node
    end)
    |> Code.eval_quoted()
    |> elem(0)
  end

  defp recorded_classes, do: MapSet.new(recorded_vectors(), &elem(&1, 0))

  defp decisions do
    for {class, arguments} <- recorded_vectors(),
        do: {class, ReleaseJobs.decode(class, arguments)}
  end

  test "every class the release modules record has a decision" do
    assert MapSet.size(recorded_classes()) == 22
    assert MapSet.equal?(recorded_classes(), MapSet.new(ReleaseJobs.classes()))
  end

  test "each recorded argument vector decodes" do
    System.put_env("SELF_HOSTED", "true")

    assert {"DataMigrations::BackfillPointCountryIdJob", [nil, 50_000, @keywords]} in recorded_vectors()
    assert {"Tracks::DeduplicationJob", [42]} in recorded_vectors()

    for {class, decision} <- decisions() do
      refute match?({:error, _}, decision), "#{class}: #{inspect(decision)}"
    end

    assert ReleaseJobs.decode("Tracks::DeduplicationJob", [42]) ==
             {:ok, Ops.TracksDedup, %{"version" => 1, "user_id" => 42}}

    assert {:ok, Ops.PointBackfill, %{"version" => 1, "operation_id" => id, "cursor" => cursor}} =
             ReleaseJobs.decode("DataMigrations::BackfillPointCountryIdJob", [
               nil,
               50_000,
               @keywords
             ])

    assert {:ok, _uuid} = Ecto.UUID.cast(id)

    assert cursor == %{
             "phase" => "country",
             "start_id" => nil,
             "batch_size" => 50_000,
             "repair_collisions" => true
           }
  end

  test "live self-hosted release vectors contain no deferred or error decisions" do
    System.put_env("SELF_HOSTED", "true")

    for {class, arguments} <- recorded_vectors() do
      case ReleaseJobs.decode(class, arguments) do
        :skip ->
          assert class in ~w(DataMigrations::BackfillFamiliesForFamilyPlanJob DataMigrations::BackfillFamilyMemberEntitlementsJob)

        {:ok, worker, args} ->
          assert Code.ensure_loaded?(worker), class
          assert function_exported?(worker, :perform, 1), class
          changeset = worker.new(args)
          assert changeset.valid?, class
          assert Ecto.Changeset.get_field(changeset, :worker) == Oban.Worker.to_string(worker)

        _ ->
          flunk("#{class} has no executable release decision")
      end
    end
  end

  test "decoded args equal what the worker builds from the forwarded command" do
    System.put_env("SELF_HOSTED", "true")

    decoded =
      for {class, arguments} <- recorded_vectors(),
          {:ok, worker, args} <- [ReleaseJobs.decode(class, arguments)],
          worker != Ops.PlacesUserId do
        payload =
          cond do
            worker == Ops.ImportBackfill ->
              Map.take(args, ["import_id", "ambient_zone"])

            class == "DataMigrations::BackfillPointCountryIdJob" ->
              @country_payloads |> List.keyfind(arguments, 0) |> elem(1)

            worker in [Ops.Anomalies, Ops.PerTracker] ->
              args["cursor"]["request"]

            true ->
              Map.fetch!(@command_payloads, class)
          end

        assert worker.args_from_command(1, payload) ==
                 {:ok, Map.drop(args, ["operation_id", "event_id"])},
               class

        class
      end

    assert MapSet.new(decoded) ==
             MapSet.put(
               MapSet.new(
                 Map.keys(@command_payloads) ++
                   ~w(DataMigrations::RecalculateAnomaliesJob DataMigrations::RecalculatePerTrackerTracksJob)
               ),
               "DataMigrations::BackfillPointCountryIdJob"
             )
  end

  test "argument vectors no release module records are refused" do
    for {class, arguments} <- [
          {"DataMigrations::BackfillPointCountryIdJob",
           [nil, 50_000, Map.put(@keywords, "extra", 1)]},
          {"DataMigrations::BackfillPointCountryIdJob", [nil, 0, @keywords]},
          {"DataMigrations::BackfillPointCountryIdJob", [1, 50_000, @keywords]},
          {"Tracks::DeduplicationJob", []},
          {"Tracks::DeduplicationJob", ["42"]},
          {"Tracks::DeduplicationJob", [0]},
          {"TransportationModes::ImportBackfillJob", [nil]},
          {"TransportationModes::ImportBackfillJob", [0]},
          {"DataMigrations::FixRouteOpacityJob", [1]},
          {"DataMigrations::DropLegacyLatLonJob", [1]},
          {"DataMigrations::BackfillFamiliesForFamilyPlanJob", [1]}
        ] do
      assert ReleaseJobs.decode(class, arguments) == {:error, :invalid_arguments},
             inspect({class, arguments})
    end
  end

  test "unknown classes are refused" do
    for class <- ["DataMigrations::NoSuchJob", "Users::RecalculateDataJob", ""] do
      assert ReleaseJobs.decode(class, []) == {:error, :unknown_class}, class
    end
  end

  test "family backfills skip self-hosted and refuse Cloud" do
    for class <-
          ~w(DataMigrations::BackfillFamiliesForFamilyPlanJob DataMigrations::BackfillFamilyMemberEntitlementsJob) do
      System.delete_env("SELF_HOSTED")
      assert ReleaseJobs.decode(class, []) == :skip

      System.put_env("SELF_HOSTED", "true")
      assert ReleaseJobs.decode(class, []) == :skip

      System.put_env("SELF_HOSTED", "false")
      assert ReleaseJobs.decode(class, []) == {:error, :cloud_family_backfill}
    end
  end

  test "decoded args are accepted by their worker and are id-only" do
    System.put_env("SELF_HOSTED", "true")

    for {class, {:ok, worker, args}} <- decisions() do
      assert worker.new(args).valid?, class
      assert Enum.all?(Map.keys(args), &(&1 in @arg_keys)), class

      for {_name, value} <- Map.get(args, "cursor", %{}) do
        assert is_integer(value) or is_boolean(value) or is_nil(value) or value in @fixed_strings or
                 (worker in [Ops.Anomalies, Ops.PerTracker] and
                    match?(
                      {:ok, _},
                      Dawarich.Users.RecalculationArgs.decode(worker.command_type(), 1, value)
                    )),
               "#{class}: #{inspect(value)}"
      end
    end
  end
end

defmodule Dawarich.ReleaseJobsSourceVectorsTest do
  use Dawarich.ScratchCase
  alias Dawarich.ReleaseMigrations.{Unreleased, V1_0_2, V1_15_2}

  @fixtures Path.expand("../fixtures/a12rel", __DIR__)

  test "historical integer source schema preserves rescued no-jobs vector" do
    seed("integer")
    assert step(V1_0_2, "20260125100000").(ScratchRepo) == {:jobs, jobs("integer_historical")}
  end

  test "historical text source schema preserves import selection and delays" do
    seed("text")
    assert step(V1_0_2, "20260125100000").(ScratchRepo) == {:jobs, jobs("text_historical")}
  end

  test "unreleased integer source vectors preserve sorted imports and fleet jobs" do
    seed("integer")
    scratch_sql!("INSERT INTO tracks(id) VALUES(56201)")
    assert step(Unreleased, "20260925100100").(ScratchRepo) == {:jobs, jobs("integer_unreleased")}
    scratch_sql!("DELETE FROM tracks")
    assert step(Unreleased, "20260925100100").(ScratchRepo) == {:jobs, jobs("integer_no_tracks")}
  end

  test "both achievement release steps preserve empty arguments and zero wait" do
    corpus = File.read!(Path.join(@fixtures, "release_vectors.json")) |> Jason.decode!()

    for {module, version} <- [{V1_15_2, "20260922120000"}, {Unreleased, "20260923180000"}] do
      vector = Enum.find(corpus["vectors"], &(&1["version"] == version))
      assert step(module, version).(ScratchRepo) == {:jobs, Enum.map(vector["jobs"], &tuple/1)}
    end
  end

  defp step(module, version), do: module.steps() |> List.keyfind(version, 0) |> elem(1)
  defp tuple(job), do: {job["class"], job["arguments"], trunc(job["due_offset"])}

  defp jobs(name) do
    corpus = File.read!(Path.join(@fixtures, "import_release_vectors.json")) |> Jason.decode!()

    corpus["vectors"]
    |> Enum.find(&(&1["id"] == name))
    |> Map.fetch!("jobs")
    |> Enum.map(&tuple/1)
  end

  defp seed(type) do
    scratch_sql!("CREATE TABLE users(id bigint PRIMARY KEY,deleted_at timestamp)")
    scratch_sql!("INSERT INTO users VALUES(987001,NULL),(987002,NULL),(987003,'2026-01-15')")
    scratch_sql!("CREATE TABLE imports(id bigint PRIMARY KEY,user_id bigint,source #{type})")
    scratch_sql!("CREATE TABLE tracks(id bigint PRIMARY KEY)")

    sources =
      if type == "text",
        do:
          ~w(google_semantic_history google_phone_takeout google_records owntracks geojson csv) ++
            [nil],
        else: [0, 1, 2, 3, 6, 10, nil]

    for {source, index} <- Enum.with_index(sources) do
      ScratchRepo.query!(
        "INSERT INTO imports VALUES($1,$2,$3)",
        [987_101 + index, if(index == 4, do: 987_003, else: 987_001), source],
        log: false
      )
    end
  end
end
