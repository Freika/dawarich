defmodule Dawarich.ReleaseJobsTest do
  use Dawarich.JobsCase

  alias Dawarich.ReleaseJobs
  alias Dawarich.ReleaseOperations, as: Ops

  @app Path.expand("../..", __DIR__)
  @keywords %{"repair_collisions" => true, "_aj_ruby2_keywords" => ["repair_collisions"]}
  @v1 %{"version" => 1}
  @arg_keys ~w(version operation_id cursor user_id)
  @command_payloads %{
    "DataMigrations::AddPointDimensionColumnsJob" => %{},
    "DataMigrations::DropLegacyLatLonJob" => %{},
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

  test "classes without a Phoenix worker defer to their owner with a versioned, id-only payload" do
    System.put_env("SELF_HOSTED", "true")

    deferred =
      for {class, arguments} <- recorded_vectors(),
          {:deferred, _owner, _payload} = outcome <- [ReleaseJobs.decode(class, arguments)],
          do: {class, outcome}

    assert Enum.sort(deferred) == [
             {"DataMigrations::BackfillAchievementsJob", {:deferred, :a12d2, @v1}},
             {"TransportationModes::ImportBackfillJob",
              {:deferred, :a7, %{"version" => 1, "import_id" => 42}}}
           ]
  end

  test "decoded args equal what the worker builds from the forwarded command" do
    System.put_env("SELF_HOSTED", "true")

    decoded =
      for {class, arguments} <- recorded_vectors(),
          {:ok, worker, args} <- [ReleaseJobs.decode(class, arguments)],
          worker != Ops.PlacesUserId do
        payload =
          cond do
            class == "DataMigrations::BackfillPointCountryIdJob" ->
              @country_payloads |> List.keyfind(arguments, 0) |> elem(1)

            worker in [Ops.Anomalies, Ops.PerTracker] ->
              args["cursor"]["request"]

            true ->
              Map.fetch!(@command_payloads, class)
          end

        assert worker.args_from_command(1, payload) == {:ok, Map.delete(args, "operation_id")},
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
