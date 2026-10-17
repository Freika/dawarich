defmodule Dawarich.TimeZoneNamesTest do
  use ExUnit.Case, async: true

  alias Dawarich.TimeZoneNames

  defmodule CatalogueRepo do
    def get_dynamic_repo, do: Process.get(__MODULE__)

    def query!("SELECT name FROM pg_timezone_names", [], log: false) do
      Process.sleep(10)

      Agent.get_and_update(get_dynamic_repo(), fn {names, reads} ->
        {%{rows: Enum.map(names, &[&1])}, {names, reads + 1}}
      end)
    end
  end

  defmodule QueryAdapter do
    def query!(sql, args), do: CatalogueRepo.query!(sql, args, log: false)
  end

  setup do
    repo = start_supervised!({Agent, fn -> {["UTC", "Asia/Tokyo"], 0} end})
    Process.put(CatalogueRepo, repo)
    %{repo: repo}
  end

  test "concurrent cold lookups share one catalogue read", %{repo: repo} do
    tasks =
      for _ <- 1..12 do
        Task.async(fn ->
          Process.put(CatalogueRepo, repo)
          TimeZoneNames.member?(CatalogueRepo, "Asia/Tokyo")
        end)
      end

    assert Enum.all?(Task.await_many(tasks))
    assert Agent.get(repo, &elem(&1, 1)) == 1
  end

  test "unknown user values do not add entries; invalidation reloads the catalogue", %{repo: repo} do
    assert TimeZoneNames.member?(CatalogueRepo, "UTC")

    for n <- 1..1000,
        do: refute(TimeZoneNames.member?(CatalogueRepo, "Unknown/#{n}"))

    assert Agent.get(repo, &elem(&1, 1)) == 1
    Agent.update(repo, fn {_, reads} -> {["UTC", "Europe/Berlin"], reads} end)
    refute TimeZoneNames.member?(CatalogueRepo, "Europe/Berlin")
    TimeZoneNames.invalidate(CatalogueRepo)
    assert TimeZoneNames.member?(CatalogueRepo, "Europe/Berlin")
    refute TimeZoneNames.member?(CatalogueRepo, "Asia/Tokyo")
    assert Agent.get(repo, &elem(&1, 1)) == 2
  end

  test "switching dynamic repositories never reuses another database's catalogue", %{repo: first} do
    assert TimeZoneNames.member?(CatalogueRepo, "Asia/Tokyo")
    {:ok, second} = Agent.start_link(fn -> {["UTC", "Europe/Berlin"], 0} end)
    Process.put(CatalogueRepo, second)
    refute TimeZoneNames.member?(CatalogueRepo, "Asia/Tokyo")
    assert TimeZoneNames.member?(CatalogueRepo, "Europe/Berlin")
    Process.put(CatalogueRepo, first)
    assert TimeZoneNames.member?(CatalogueRepo, "Asia/Tokyo")
    assert Agent.get(first, &elem(&1, 1)) == 1
    assert Agent.get(second, &elem(&1, 1)) == 1
    Agent.stop(second)
  end

  test "opaque query adapters read without assuming a dynamic repository", %{repo: repo} do
    assert TimeZoneNames.member?(QueryAdapter, "Asia/Tokyo")
    Agent.update(repo, fn {_, reads} -> {["UTC", "Europe/Berlin"], reads} end)
    refute TimeZoneNames.member?(QueryAdapter, "Asia/Tokyo")
    assert TimeZoneNames.member?(QueryAdapter, "Europe/Berlin")
    assert TimeZoneNames.invalidate(QueryAdapter) == :ok
    assert Agent.get(repo, &elem(&1, 1)) == 3
  end
end
