defmodule Dawarich.ReleaseMigrator.RealLedgerTest do
  use ExUnit.Case, async: true

  alias Dawarich.RailsTree
  alias Dawarich.ReleaseMigrator.{Floor, Ledger}

  defp through(release) do
    {states, _later} = RailsTree.split_at(release)
    states |> Enum.flat_map(& &1["schema_added"]) |> MapSet.new()
  end

  defp known do
    floor = through(Floor.release())
    Enum.reject(RailsTree.versions("migrate"), &MapSet.member?(floor, &1))
  end

  defp everything, do: MapSet.union(through(Floor.release()), MapSet.new(known()))

  defp classify(ledger), do: Ledger.classify(ledger, known())

  test "a 1.0.0 ledger is accepted with every later release pending" do
    assert classify(through("0.37.2")) == {:pending, known()}
  end

  test "a 0.37.0 ledger is refused at 0.37.2" do
    assert classify(through("0.37.0")) == {:below_floor, "0.37.2"}
  end

  test "the database stuck part-way through 0.37.0 is refused at 0.37.0" do
    stuck = MapSet.union(through("0.36.3"), MapSet.new(~w[20251226170919 20251227000001]))
    assert classify(stuck) == {:below_floor, "0.37.0"}
  end

  test "a 0.9.12 schema.rb install, define version included, is refused at 0.12.0" do
    assert classify(MapSet.put(through("0.9.12"), "20240808121027")) == {:below_floor, "0.12.0"}
  end

  test "every version, with or without the removed RailsPulse version, is current" do
    assert classify(everything()) == :current
    assert classify(MapSet.delete(everything(), "20251228163703")) == :current
  end

  test "define versions a schema.rb install carried through a Rails upgrade to 1.0.0 are tolerated" do
    for phantom <- Ledger.schema_rb_define_versions() do
      assert classify(MapSet.put(through("0.37.2"), phantom)) == {:pending, known()}, phantom
    end
  end

  test "interrupted upgrades after the floor resume in global version order" do
    assert {:pending, ["20260112192240" | _]} =
             classify(MapSet.put(through("0.37.2"), "20260108192905"))

    assert {:pending, ["20260207075817", "20260208223255", "20260301202147" | _]} =
             classify(MapSet.put(through("1.3.1"), "20260301201446"))
  end

  test "a release candidate's extra migration is refused as newer" do
    assert classify(MapSet.put(everything(), "29990101000000")) == {:newer, ["29990101000000"]}
  end
end
