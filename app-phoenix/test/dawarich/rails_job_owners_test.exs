defmodule Dawarich.RailsJobOwnersTest do
  use ExUnit.Case, async: true

  alias Dawarich.{RailsJobOwners, RailsTree, ReleaseJobs}
  alias Dawarich.Jobs.Registry

  test "coexistence cache and boot jobs remain explicit drain blockers rather than claimed native schedules" do
    owners = RailsJobOwners.owners()
    assert owners["Cache::CleaningJob"] == {:slice, :a12d1}
    assert owners["Cache::PreheatingJob"] == {:oban, ["cron:cache_preheating_job"], :a12d1}
    assert owners["Cache::UserPreheatingJob"] == {:oban, ["command:cache.preheat_user"], :a12d1}

    for class <- ~w(Cache::CleaningJob Cache::PreheatingJob Cache::UserPreheatingJob),
        do: assert(String.contains?(RailsJobOwners.coexistence_reasons()[class], "retained"))

    assert RailsTree.read("config/initializers/cache_jobs.rb") =~ "cache_jobs_scheduled"
    assert RailsTree.read("app/services/cache/clean.rb") =~ "delete_control_flag"
    assert Registry.claimable() == []
    refute "Cache::CleaningJob" in ReleaseJobs.classes()
    refute "Cache::PreheatingJob" in ReleaseJobs.classes()
    refute "Cache::UserPreheatingJob" in ReleaseJobs.classes()
    refute Enum.any?(Registry.entries(), &String.contains?(&1.key, "cleaning"))
  end

  test "every Rails job class has an owner decision and every decision names a Rails job class" do
    scanned = MapSet.new(job_files(), &class_for/1)
    owned = MapSet.new(RailsJobOwners.classes())

    assert MapSet.equal?(scanned, owned),
           "unowned: #{inspect(Enum.sort(MapSet.difference(scanned, owned)))}; " <>
             "stale: #{inspect(Enum.sort(MapSet.difference(owned, scanned)))}"

    assert MapSet.size(scanned) == 125
  end

  test "owner decisions use the allowed vocabulary, name live registry keys, and cover every key" do
    keys = MapSet.new(Registry.entries(), & &1.key)
    slices = RailsJobOwners.slices()

    used =
      Enum.flat_map(RailsJobOwners.owners(), fn {class, owner} ->
        case owner do
          {:oban, [_ | _] = owned} ->
            assert Enum.all?(owned, &MapSet.member?(keys, &1)), class
            owned

          {:oban, [_ | _] = owned, rest} ->
            assert Enum.all?(owned, &MapSet.member?(keys, &1)), class
            assert rest == :retire or rest in slices, class
            owned

          {:migrator, worker} ->
            assert class in ReleaseJobs.classes(), class
            assert Code.ensure_loaded?(worker), class
            []

          {:slice, slice} ->
            assert slice in slices, class
            []

          :retire ->
            []
        end
      end)

    used = used ++ Map.keys(RailsJobOwners.native_producers())

    assert MapSet.equal?(MapSet.new(used), keys),
           "registry keys without a Rails class: #{inspect(Enum.sort(MapSet.difference(keys, MapSet.new(used))))}"
  end

  test "config/schedule.yml holds the 24 crons the table was frozen against, each with an owner" do
    classes =
      ~r/^\s+class: "([^"]+)"/m
      |> Regex.scan(RailsTree.read("config/schedule.yml"), capture: :all_but_first)
      |> List.flatten()

    assert length(classes) == 24

    for class <- classes,
        do: assert(Map.has_key?(RailsJobOwners.owners(), class), "#{class} has no owner")
  end

  test "the classes the release migrator records carry the owner their decoder outcome names" do
    workers = Map.new(Registry.entries(), &{&1.key, &1.worker})

    for class <- ReleaseJobs.classes() do
      outcome = ReleaseJobs.decode(class, sample_arguments(class))

      case Map.fetch!(RailsJobOwners.owners(), class) do
        {:oban, keys} ->
          assert {:ok, worker, _args} = outcome, class
          assert worker in Enum.map(keys, &Map.fetch!(workers, &1)), class

        {:migrator, worker} ->
          assert match?({:ok, ^worker, _args}, outcome), class

        {:slice, slice} ->
          assert match?({:deferred, ^slice, _payload}, outcome), class

        :retire ->
          assert outcome in [:skip, {:error, :cloud_family_backfill}], class
      end
    end
  end

  defp sample_arguments("Tracks::DeduplicationJob"), do: [1]
  defp sample_arguments("TransportationModes::ImportBackfillJob"), do: [1]
  defp sample_arguments(_class), do: []

  defp job_files do
    "app/jobs/**/*.rb"
    |> RailsTree.wildcard()
    |> Enum.reject(
      &(&1 == "app/jobs/application_job.rb" or String.starts_with?(&1, "app/jobs/concerns/"))
    )
  end

  defp class_for(file) do
    file
    |> String.replace_prefix("app/jobs/", "")
    |> String.replace_suffix(".rb", "")
    |> Macro.camelize()
    |> String.replace(".", "::")
  end
end
