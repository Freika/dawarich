defmodule Dawarich.ReleaseMigrator.LedgerTest do
  use ExUnit.Case, async: true

  alias Dawarich.ReleaseMigrator.{Floor, Ledger}

  @known ~w[20990101000001 20990101000002 20990115000001 20990201000001]

  defp ledger(versions), do: MapSet.new(Floor.versions() ++ versions)

  test "a database without a schema_migrations table is fresh" do
    assert Ledger.classify(nil, @known) == :fresh
  end

  test "an empty schema_migrations is fresh too" do
    assert Ledger.classify(MapSet.new(), @known) == :fresh
    assert Ledger.below_floor(MapSet.new()) == nil
  end

  test "a ledger at the floor has every known version pending, in version order" do
    assert Ledger.classify(ledger([]), Enum.reverse(@known)) == {:pending, @known}
  end

  test "a ledger stopped part-way through anything after the floor resumes from what is missing" do
    assert Ledger.classify(ledger(~w[20990101000001 20990115000001]), @known) ==
             {:pending, ~w[20990101000002 20990201000001]}
  end

  test "a ledger holding every known version is current" do
    assert Ledger.classify(ledger(@known), @known) == :current
  end

  test "a version this image does not know is refused as newer" do
    assert Ledger.classify(ledger(@known ++ ["29990101000000"]), @known) ==
             {:newer, ["29990101000000"]}
  end

  test "the removed RailsPulse version and phantom schema.rb define versions are tolerated" do
    ledger = ledger(@known ++ ~w[20251228163703 20241030152025 20250930150256])
    assert Ledger.classify(ledger, @known) == :current
  end

  test "a ledger holding no Dawarich migration at all is refused as not Dawarich, not below the floor" do
    assert Ledger.classify(MapSet.new(~w[10000101000001 10000101000002 10000101000003]), @known) ==
             {:not_dawarich, 3}
  end

  test "a ledger missing any version up to the floor is below it, named by the oldest state it lacks" do
    assert Ledger.classify(MapSet.new(Floor.versions() -- ~w[20260103114630]), @known) ==
             {:below_floor, "0.37.2"}

    assert Ledger.classify(
             MapSet.new(Floor.versions() -- ~w[20240808121027 20251227223614]),
             @known
           ) == {:below_floor, "0.12.0"}

    assert Ledger.classify(MapSet.new(~w[20220325100310 29990101000000]), @known) ==
             {:below_floor, "0.0.8"}
  end
end
