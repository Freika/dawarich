defmodule Dawarich.AfterCommitGuardTest do
  use ExUnit.Case, async: true

  test "transaction closures cannot reach inline cache eviction or epoch bumps" do
    assert violations(Path.wildcard("lib/**/*.ex")) == []
  end

  test "P2 alias cache deletion is rejected inside a transaction" do
    assert_fixture("alias Dawarich.TtlCache, as: Cache", "Cache.delete(key)")
  end

  test "P2 piped UNLINK is rejected inside a transaction" do
    assert_fixture("", "[\"UNLINK\", key] |> Dawarich.Redis.cache_command()")
  end

  test "R1 aliased Transaction.run rejects rollback-surviving cache eviction" do
    assert_source("""
    alias Dawarich.Transaction, as: Tx
    def write(repo, key), do: Tx.run(repo, fn -> Dawarich.TtlCache.delete(key) end)
    """)
  end

  test "R1 local function capture rejects rollback-surviving cache eviction" do
    assert_source("""
    def write(repo), do: repo.transaction(&clear/0)
    defp clear, do: Dawarich.TtlCache.delete({__MODULE__, :synthetic})
    """)
  end

  test "R1 aliased Repo.transaction follows remote function captures" do
    assert_source("""
    alias Dawarich.Repo, as: Database
    alias GuardProbe, as: Cleaner
    def write, do: Database.transaction(&Cleaner.clear/0)
    def clear, do: Dawarich.TtlCache.delete(:synthetic)
    """)
  end

  test "R1 Dawarich.Transaction.run follows captured eviction functions" do
    assert_source("""
    def write(repo), do: Dawarich.Transaction.run(repo, &clear/0, mode: :savepoint)
    defp clear, do: Dawarich.TtlCache.delete(:synthetic)
    """)
  end

  test "R1 Ecto.Multi.run follows inline and captured run callbacks" do
    for callback <- [
          "fn _, _ -> Dawarich.TtlCache.delete(:synthetic) end",
          "&clear/2",
          "&GuardProbe.clear/2"
        ] do
      assert_source("""
      alias Ecto.Multi, as: Batch
      def write(repo), do: Batch.new() |> Batch.run(:clear, #{callback}) |> repo.transaction()
      def clear(_, _), do: Dawarich.TtlCache.delete(:synthetic)
      """)
    end
  end

  test "R1 Ecto.Multi.run follows module function argument callbacks" do
    assert_source("""
    alias Ecto.Multi, as: Batch
    def write(repo), do: repo.transaction(Batch.run(Batch.new(), :clear, GuardProbe, :clear, []))
    def clear(_, _), do: Dawarich.TtlCache.delete(:synthetic)
    """)
  end

  test "R1 statically bound transaction callbacks and Multi steps are followed" do
    for callback <- [
          "fn -> Dawarich.TtlCache.delete(:synthetic) end",
          "&clear/0",
          "Ecto.Multi.new() |> Ecto.Multi.run(:clear, &clear/2)"
        ] do
      assert_source("""
      def write(repo) do
        work = #{callback}
        repo.transaction(work)
      end
      defp clear, do: Dawarich.TtlCache.delete(:synthetic)
      defp clear(_, _), do: Dawarich.TtlCache.delete(:synthetic)
      """)
    end
  end

  test "R1 transaction wrappers propagate their callback argument" do
    assert_source("""
    def write(repo), do: commit(repo, &clear/0)
    defp commit(repo, callback), do: repo.transaction(callback)
    defp clear, do: Dawarich.TtlCache.delete(:synthetic)
    """)
  end

  test "R1 current and explicit module references resolve in captured callbacks" do
    for target <- ["__MODULE__", "Elixir.GuardProbe", "Cleaner", ":\"Elixir.GuardProbe\""],
        entry <- [
          "repo.transaction(&#{target}.clear/0)",
          "repo.transaction(Ecto.Multi.run(Ecto.Multi.new(), :clear, #{target}, :clear, []))"
        ] do
      assert_source("""
      alias __MODULE__, as: Cleaner
      def write(repo), do: #{entry}
      def clear, do: Dawarich.TtlCache.delete(:synthetic)
      def clear(_, _), do: Dawarich.TtlCache.delete(:synthetic)
      """)
    end
  end

  test "R1 chained transaction aliases resolve before transaction recognition" do
    assert_source("""
    alias Dawarich, as: D
    alias D.Transaction, as: Tx
    alias D.TtlCache, as: Cache
    def write(repo), do: Tx.run(repo, fn -> Cache.delete(:synthetic) end)
    """)
  end

  defp assert_source(source) do
    path =
      Path.join(System.tmp_dir!(), "after-commit-guard-#{System.unique_integer([:positive])}.ex")

    File.write!(path, "defmodule GuardProbe do\n#{source}\nend")

    try do
      assert length(violations([path])) == 1
    after
      File.rm!(path)
    end
  end

  defp assert_fixture(alias_source, expression) do
    path =
      Path.join(System.tmp_dir!(), "after-commit-guard-#{System.unique_integer([:positive])}.ex")

    File.write!(
      path,
      "defmodule GuardProbe do\n#{alias_source}\ndef write(repo, key), do: repo.transaction(fn -> #{expression} end)\nend"
    )

    try do
      assert length(violations([path])) == 1
    after
      File.rm!(path)
    end
  end

  defp violations(paths), do: Dawarich.Test.AfterCommitGuard.violations(paths)
end
