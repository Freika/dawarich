defmodule Dawarich.ReleaseMigrations.V1_15_0Test do
  use Dawarich.ScratchCase

  alias Dawarich.RailsTree
  alias Dawarich.ReleaseMigration.UnportedEffect
  alias Dawarich.ReleaseMigrations.V1_15_0

  test "the InstanceSettings::Backfill stop watches every InstanceSettings::Registry variable" do
    source = RailsTree.read("app/services/instance_settings/registry.rb")

    variables =
      ~r/\benv_var:\s*(['"])(.*?)\1/
      |> Regex.scan(source, capture: :all_but_first)
      |> Enum.map(&List.last/1)

    assert length(Regex.scan(~r/\bDefinition\.new\b/, source)) == length(variables)
    assert Enum.sort(V1_15_0.registry_variables()) == Enum.sort(variables)
  end

  test "the InstanceSettings::Backfill stop reads a variable as set exactly when Ruby's strip leaves it non-empty" do
    saved = Map.new(V1_15_0.registry_variables(), &{&1, System.get_env(&1)})
    Enum.each(V1_15_0.registry_variables(), &System.delete_env/1)
    scratch_sql!("CREATE TABLE users (id bigint)")
    {_, backfill} = List.keyfind(V1_15_0.steps(), "20260901150000", 0)

    try do
      assert backfill.(ScratchRepo) == nil
      System.put_env("STORE_GEODATA", " \t\n\v\f\r")
      assert backfill.(ScratchRepo) == nil
      System.put_env("STORE_GEODATA", " ")
      assert_raise UnportedEffect, fn -> backfill.(ScratchRepo) end
    after
      Enum.each(saved, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end
  end
end
