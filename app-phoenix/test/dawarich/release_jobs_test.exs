defmodule Dawarich.ReleaseJobsTest do
  use ExUnit.Case, async: false

  alias Dawarich.{ReleaseEffectInventory, ReleaseJobs}
  alias Dawarich.ReleaseOperations, as: Ops

  @app Path.expand("../..", __DIR__)
  @keywords %{"repair_collisions" => true, "_aj_ruby2_keywords" => ["repair_collisions"]}
  @arg_keys ~w(version operation_id cursor user_id)
  @command_payloads %{
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

    assert ReleaseJobs.decode("TransportationModes::ImportBackfillJob", [5]) == {:deferred, :a7}
  end

  test "decoded args equal what the worker builds from the forwarded command" do
    System.put_env("SELF_HOSTED", "true")

    decoded =
      for {class, arguments} <- recorded_vectors(),
          {:ok, worker, args} <- [ReleaseJobs.decode(class, arguments)],
          worker != Ops.PlacesUserId do
        payload =
          if class == "DataMigrations::BackfillPointCountryIdJob",
            do: @country_payloads |> List.keyfind(arguments, 0) |> elem(1),
            else: Map.fetch!(@command_payloads, class)

        assert worker.args_from_command(1, payload) == {:ok, Map.delete(args, "operation_id")},
               class

        class
      end

    assert MapSet.new(decoded) ==
             MapSet.put(
               MapSet.new(Map.keys(@command_payloads)),
               "DataMigrations::BackfillPointCountryIdJob"
             )
  end

  test "a keyword marker with an extra key is refused" do
    keywords = Map.put(@keywords, "extra", 1)

    assert ReleaseJobs.decode("DataMigrations::BackfillPointCountryIdJob", [nil, 50_000, keywords]) ==
             {:error, :invalid_arguments}

    assert ReleaseJobs.decode("Tracks::DeduplicationJob", ["42"]) == {:error, :invalid_arguments}

    assert ReleaseJobs.decode("DataMigrations::FixRouteOpacityJob", [1]) ==
             {:error, :invalid_arguments}
  end

  test "unknown classes are refused" do
    assert ReleaseJobs.decode("DataMigrations::NoSuchJob", []) == {:error, :unknown_class}
  end

  test "family backfills skip self-hosted and refuse Cloud" do
    for class <-
          ~w(DataMigrations::BackfillFamiliesForFamilyPlanJob DataMigrations::BackfillFamilyMemberEntitlementsJob) do
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
        assert is_integer(value) or is_boolean(value) or is_nil(value) or value in @fixed_strings,
               "#{class}: #{inspect(value)}"
      end
    end
  end

  test "decisions agree with the C3a inventory owners" do
    System.put_env("SELF_HOSTED", "true")
    decisions = Map.new(decisions())

    for %{class: class, owner: owner} <- ReleaseEffectInventory.job_classes() do
      expected =
        case decisions[class] do
          {:ok, _worker, _args} -> :a1x_wave6
          :skip -> :a1x_wave6
          {:deferred, owner} -> owner
        end

      assert owner == expected, class
    end
  end
end
