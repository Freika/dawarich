defmodule Dawarich.AfterCommitWrapperGuardTest do
  use ExUnit.Case, async: true

  alias Dawarich.Test.AfterCommitGuard

  @tag :sa_gate_graph_cost
  test "ownership guard bounds converging graph work while retaining reachable eviction checks" do
    layers =
      Enum.map_join(0..10, "\n", fn n ->
        "def layer#{n}, do: [layer#{n + 1}(), layer#{n + 1}()]"
      end)

    source = """
    defmodule GuardConvergence do
      def write(repo), do: repo.transaction(fn -> layer0() end)
      #{layers}
      def layer11, do: :ok
      def unreachable, do: Dawarich.TtlCache.delete(:synthetic)
    end
    """

    with_source(source, fn path ->
      {:reductions, before} = Process.info(self(), :reductions)
      violations = AfterCommitGuard.violations([path])
      {:reductions, after_count} = Process.info(self(), :reductions)
      assert violations == []
      assert after_count - before < 50_000

      File.write!(
        path,
        String.replace(source, "def layer11, do: :ok", "def layer11, do: unreachable()")
      )

      assert [{^path, {"Elixir.GuardConvergence", :write, 1}, _}] =
               AfterCommitGuard.violations([path])
    end)
  end

  test "R2 production ownership closure follows the caller's captured and aliased callbacks" do
    sources =
      for callback <- ["&clear/0", "&Cleaner.clear/0", "fn -> Cache.delete(:synthetic) end"] do
        """
        alias Dawarich.Jobs.Ownership, as: Owner
        alias Dawarich.TtlCache, as: Cache
        alias __MODULE__, as: Cleaner
        def write(repo) do
          work = #{callback}
          Owner.with_owner(repo, "synthetic", :oban, work)
        end
        def clear, do: Cache.delete(:synthetic)
        """
      end

    assert_probes(sources)
  end

  test "R2 actual nightly batch eviction is reachable through the ownership closure" do
    original = "lib/dawarich/geocoding/nightly_sweep.ex"
    marker = "  defp batch(repo, oban, args, opts) do"
    source = File.read!(original)
    assert String.contains?(source, marker)

    source =
      String.replace(
        source,
        marker,
        marker <> "\n    Dawarich.TtlCache.delete({__MODULE__, :synthetic})"
      )

    with_source(source, fn path ->
      paths = Enum.reject(Path.wildcard("lib/**/*.ex"), &(&1 == original)) ++ [path]

      assert Enum.any?(AfterCommitGuard.violations(paths), fn {file, key, target} ->
               file == path and key == {"Elixir.Dawarich.Geocoding.NightlySweep", :run, 4} and
                 target == {"Elixir.Dawarich.Geocoding.NightlySweep", :batch, 4}
             end)
    end)
  end

  test "R2 callback accepting transaction wrapper census rejects inline eviction" do
    sources =
      for entry <- [
            "Dawarich.Jobs.Processed.once(repo, :event, :handler, work)",
            "Dawarich.AfterCommit.with_visibility(repo, :keys, %{}, work)",
            "Dawarich.AfterCommit.once(repo, :event, work)",
            "Dawarich.Visits.WebEffects.transact(repo, work)",
            "Dawarich.Tracks.BackfillWalks.select(repo, :user, :walk, :cursor, work)",
            "Dawarich.Tracks.BackfillWalks.schedule(repo, :user, :zone, :now, work)",
            "Dawarich.Tracks.BackfillWalks.advance(repo, :step, :now, work)",
            "Dawarich.Tags.Writes.transaction(repo, work)",
            "Dawarich.Tracks.SegmentEditor.transaction(repo, work)",
            "Dawarich.Points.ApiWrites.commit(repo, work)",
            "Dawarich.Imports.Download.fenced(repo, :user, :id, :snapshot, %{}, work)",
            "Dawarich.Imports.PrepareDownloadWorker.effect(repo, job, :source, work)",
            "Dawarich.Imports.ExtractionRemovalWorker.effect!(repo, job, work)",
            "Dawarich.Imports.Lease.effect!(lease, work)",
            "Dawarich.Imports.Lease.terminal_effect!(lease, work)",
            "Dawarich.Imports.DestroyLease.effect!(lease, work)",
            "Dawarich.EnhancedImport.RequestFence.run(repo, job, :extract, fn fence -> fence.(work, true) end)"
          ] do
        """
        alias Dawarich.TtlCache, as: Cache
        def write(repo, lease, job) do
          work = fn -> Cache.delete(:synthetic) end
          #{entry}
        end
        """
      end

    assert_probes(sources)
  end

  test "R2 nested wrapper closures retain wrapper and caller module contexts" do
    assert_probe("""
    alias Dawarich.TtlCache, as: Cache
    def write(repo), do: GuardWrapper.commit(repo, &clear/0)
    def clear, do: Cache.delete(:synthetic)
    end
    defmodule GuardWrapper do
      alias Dawarich.Jobs.Ownership, as: Owner
      def commit(repo, callback) do
        work = fn -> invoke(callback) end
        Owner.with_owner(repo, "synthetic", :oban, work)
      end
      defp invoke(callback), do: callback.()
    """)
  end

  test "post-commit eviction remains outside transactional reachability" do
    with_source(
      """
      defmodule PostcommitProbe do
        alias Dawarich.TtlCache, as: Cache
        def write(repo) do
          {:ok, _} = repo.transaction(fn -> :ok end)
          Cache.delete(:synthetic)
        end
        def wrapped(repo), do: after_write(repo, fn -> Cache.delete(:synthetic) end)
        defp after_write(repo, callback) do
          {:ok, _} = repo.transaction(fn -> :ok end)
          callback.()
        end
      end
      """,
      fn path ->
        assert AfterCommitGuard.violations(Path.wildcard("lib/**/*.ex") ++ [path]) == []
      end
    )
  end

  test "R2 area write callbacks exclude the post-commit destroy action" do
    assert AfterCommitGuard.violations([
             "lib/dawarich_web/api/areas_controller.ex",
             "lib/dawarich_web/api/write_response.ex",
             "lib/dawarich/areas/api.ex"
           ]) == []
  end

  defp assert_probe(source), do: assert_probes([source])

  defp assert_probes(sources) do
    probes = Enum.with_index(sources, fn source, i -> {"Elixir.GuardProbe#{i}", source} end)

    source =
      Enum.map_join(probes, "\n", fn {module, source} ->
        "defmodule #{module} do\n#{source}\nend"
      end)

    with_source(source, fn path ->
      violations = AfterCommitGuard.violations(Path.wildcard("lib/**/*.ex") ++ [path])

      for {module, source} <- probes do
        assert Enum.any?(violations, fn
                 {^path, {^module, :write, _}, _} -> true
                 _ -> false
               end),
               source
      end
    end)
  end

  defp with_source(source, check) do
    path =
      Path.join(
        System.tmp_dir!(),
        "after-commit-wrapper-#{System.unique_integer([:positive])}.ex"
      )

    File.write!(path, source)

    try do
      check.(path)
    after
      File.rm!(path)
    end
  end
end
