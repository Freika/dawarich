defmodule Dawarich.ReleaseMigrations.InlineEffectsTest do
  use ExUnit.Case, async: true

  alias Dawarich.ReleaseMigrations

  @root Path.expand("../../../..", __DIR__)
  @effects Path.join(@root, "app-phoenix/lib/dawarich/release_migrations/effects/*.ex")

  test "inline_effects.tsv is sorted, and each row names an existing Rails file and a registered release" do
    releases = Enum.map(ReleaseMigrations.all(), & &1.release())

    assert rows() == Enum.sort(rows())

    for row <- rows() do
      assert [path, release] = row
      assert File.regular?(Path.join(@root, path)), "#{path} is not in the Rails tree"
      assert release in releases, "#{release} is not a registered release"
    end
  end

  test "every inline effect module has a row naming a release whose module calls it" do
    listed = Enum.map(rows(), &List.last/1)

    for path <- Path.wildcard(@effects) do
      name = Macro.camelize(Path.basename(path, ".ex"))

      callers =
        for module <- ReleaseMigrations.all(),
            File.read!(List.to_string(module.module_info(:compile)[:source])) =~
              ~r/\bEffects\.#{name}\b/,
            do: module.release()

      assert Enum.any?(callers, &(&1 in listed)),
             "Effects.#{name} is called by #{inspect(callers)}, inline_effects.tsv lists #{inspect(listed)}"
    end
  end

  defp rows do
    @root
    |> Path.join("scripts/schema_parity/inline_effects.tsv")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&String.split(&1, "\t"))
  end
end
