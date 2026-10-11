defmodule Dawarich.Build.NativeAssetBudgetTest do
  use ExUnit.Case, async: true
  alias Dawarich.Build.NativeAssetBudget, as: Budget

  test "native closure budgets accept each frozen boundary and reject a byte over every cap" do
    sizes = Map.new(Budget.caps(), fn {name, limits} -> {name, Map.put(limits, :chunks, 1)} end)
    assert Budget.within?(sizes)

    for name <- Map.keys(sizes), field <- [:raw, :gzip] do
      over = put_in(sizes, [name, field], sizes[name][field] + 1)
      refute Budget.within?(over)
    end
  end

  test "native closure budgets refuse missing unknown or invalid measurement receipts" do
    sizes = Map.new(Budget.caps(), fn {name, limits} -> {name, Map.put(limits, :chunks, 1)} end)

    for invalid <- [
          Map.delete(sizes, :map),
          Map.put(sizes, :unknown, sizes.app),
          put_in(sizes, [:app, :raw], -1),
          put_in(sizes, [:map, :gzip], "1"),
          put_in(sizes, [:video, :chunks], 0)
        ] do
      refute Budget.within?(invalid)
    end
  end
end
