defmodule Dawarich.ReleaseMigrationsTest do
  use ExUnit.Case, async: true

  alias Dawarich.{RailsTree, ReleaseMigration, ReleaseMigrations}
  alias Dawarich.ReleaseMigrations.Unreleased
  alias Dawarich.ReleaseMigrator.{Floor, Ledger}

  @app Path.expand("../..", __DIR__)

  test "finds a registered release by name and keeps Unreleased last" do
    assert ReleaseMigrations.find("unreleased") == Unreleased
    assert ReleaseMigrations.find("0.0.0") == nil
    assert List.last(ReleaseMigrations.all()) == Unreleased
  end

  test "release modules follow db/release_migrations.json and end with Unreleased" do
    releases = Enum.map(ReleaseMigrations.all(), & &1.release())
    assert List.last(releases) == "unreleased"
    ported = Enum.drop(releases, -1)

    assert ported ==
             Enum.filter(Enum.map(RailsTree.states(), & &1["first_release"]), &(&1 in ported))
  end

  test "each release module holds its state's migrations that db/migrate and db/data still ship" do
    schema = RailsTree.versions("migrate")
    data = RailsTree.versions("data")
    by_release = Map.new(RailsTree.states(), &{&1["first_release"], &1})

    for module <- ReleaseMigrations.all(), module.release() != "unreleased" do
      state = Map.fetch!(by_release, module.release())

      assert ReleaseMigration.versions(module) ==
               state["schema_added"] |> Enum.filter(&(&1 in schema)) |> Enum.sort(),
             module.release()

      assert module.data_versions() ==
               state["data_added"] |> Enum.filter(&(&1 in data)) |> Enum.sort(),
             module.release()
    end
  end

  test "Unreleased holds exactly the migrations no release lists yet" do
    listed = Enum.flat_map(RailsTree.states(), & &1["schema_added"])
    listed_data = Enum.flat_map(RailsTree.states(), & &1["data_added"])
    unreleased = ReleaseMigrations.find("unreleased")

    assert ReleaseMigration.versions(unreleased) ==
             Enum.reject(RailsTree.versions("migrate"), &(&1 in listed))

    assert unreleased.data_versions() ==
             Enum.reject(RailsTree.versions("data"), &(&1 in listed_data))
  end

  test "a step runs outside a transaction exactly when its Rails migration disables the DDL transaction" do
    for module <- ReleaseMigrations.all(), step <- module.steps() do
      {version, _fun, transaction?} = ReleaseMigration.normalize(step)

      assert transaction? == not RailsTree.disables_ddl_transaction?(version),
             "#{module.release()} #{version}"
    end
  end

  test "release modules never change session settings" do
    offenders =
      ["lib/dawarich/release_migrations/**/*.ex", "priv/release_migrations/**/*.sql"]
      |> Enum.flat_map(&Path.wildcard(Path.join(@app, &1)))
      |> Enum.filter(fn path ->
        File.read!(path) =~
          ~r/(\A|[;"'|(\[{<])\s*(RESET|SET)\b(?!\s+LOCAL\b)|set_config\s*\((?:[^()]|(?<p>\((?:[^()]|(?&p))*\)))*,\s*false\s*\)/i
      end)

    assert offenders == []
  end

  test "the removed-version list is every listed migration db/migrate no longer ships" do
    shipped = RailsTree.versions("migrate")

    listed =
      RailsTree.states() |> Enum.flat_map(& &1["schema_added"]) |> Enum.uniq() |> Enum.sort()

    assert Ledger.removed_versions() == Enum.reject(listed, &(&1 in shipped))
  end

  test "the floor is 1.0.0's state and every state before it, with the migrations db/migrate still ships" do
    {through_floor, _ported} = RailsTree.split_at(Floor.release())
    assert "1.0.0" in List.last(through_floor)["releases"]
    shipped = RailsTree.versions("migrate")

    expected =
      for state <- through_floor,
          versions = state["schema_added"] |> Enum.filter(&(&1 in shipped)) |> Enum.sort(),
          versions != [],
          do: {state["first_release"], versions}

    assert Floor.states() == expected
  end

  test "release modules exist only for states after the 1.0.0 floor" do
    {through_floor, _ported} = RailsTree.split_at(Floor.release())
    floor_releases = Enum.map(through_floor, & &1["first_release"])

    assert Enum.filter(ReleaseMigrations.all(), &(&1.release() in floor_releases)) == []
  end
end
