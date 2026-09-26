defmodule Dawarich.ReleaseMigrations.EffectInventoryTest do
  use ExUnit.Case, async: true

  alias Dawarich.{RailsTree, ReleaseEffectInventory}

  @app Path.expand("../../..", __DIR__)
  @job_class ~r/\bjob\(\s*"([^"]+)"/
  @unported_class ~r/unported!\(\s*"([^"]+)"\)/

  test "every job/2,3 class the release modules pass is classified in the inventory" do
    found = MapSet.new(found_job_classes())
    inventory = MapSet.new(ReleaseEffectInventory.job_classes(), & &1.class)

    assert MapSet.equal?(found, inventory), mismatch_message(found, inventory)
  end

  test "every unported!/1 site the release modules call is classified in the inventory" do
    found = MapSet.new(found_unported_sites())
    inventory = MapSet.new(ReleaseEffectInventory.unported_sites(), &{&1.site, &1.class})

    assert MapSet.equal?(found, inventory), mismatch_message(found, inventory)
  end

  test "every inventoried class's Rails file exists and defines that class" do
    entries =
      Enum.uniq_by(
        ReleaseEffectInventory.job_classes() ++ ReleaseEffectInventory.unported_sites(),
        &{&1.class, &1.rails_file}
      )

    for %{class: class, rails_file: file} <- entries do
      assert RailsTree.defines_class?(file, class), "#{class} is not defined in #{file}"
    end
  end

  test "every job class owner is one of the three C3a owner atoms" do
    for %{owner: owner} <- ReleaseEffectInventory.job_classes() do
      assert owner in [:a1x_wave5, :a1x_wave6, :unreachable]
    end
  end

  defp found_job_classes do
    release_module_paths()
    |> Enum.flat_map(&Regex.scan(@job_class, File.read!(&1), capture: :all_but_first))
    |> List.flatten()
    |> Enum.uniq()
  end

  defp found_unported_sites do
    for path <- release_module_paths(),
        {line, index} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
        [class] <- Regex.scan(@unported_class, line, capture: :all_but_first) do
      {"#{Path.basename(path)}:#{index}", class}
    end
  end

  defp release_module_paths do
    @app |> Path.join("lib/dawarich/release_migrations/*.ex") |> Path.wildcard() |> Enum.sort()
  end

  defp mismatch_message(found, inventory) do
    "unclassified: #{inspect(MapSet.to_list(MapSet.difference(found, inventory)))}; " <>
      "stale: #{inspect(MapSet.to_list(MapSet.difference(inventory, found)))}"
  end
end
