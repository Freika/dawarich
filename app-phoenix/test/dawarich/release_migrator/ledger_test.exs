defmodule Dawarich.ReleaseMigrator.LedgerTest do
  use ExUnit.Case, async: true

  alias Dawarich.ReleaseMigrator.Ledger

  @known ~w[20990101000001 20990101000002 20990115000001 20990201000001]

  defp ledger(versions), do: MapSet.new(versions)

  test "a database without a schema_migrations table is fresh" do
    assert Ledger.classify(nil, @known) == :fresh
  end

  test "an empty ledger has every known version pending, in version order" do
    assert Ledger.classify(ledger([]), Enum.reverse(@known)) == {:pending, @known}
  end

  test "a ledger stopped part-way through anything resumes from what is missing" do
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
end
