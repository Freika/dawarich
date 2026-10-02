defmodule Dawarich.Digests.RefreshPatternsTest do
  use ExUnit.Case, async: true
  alias Dawarich.Digests.Refresh.Patterns

  test "percentages match Rails including rounding that need not sum100" do
    assert Patterns.percentages(
             [{"morning", 1}, {"night", 1}, {"afternoon", 1}],
             ~w(night morning afternoon evening)
           ) ==
             %{"night" => 33, "morning" => 33, "afternoon" => 33, "evening" => 0}

    assert Patterns.percentages([], ~w(night morning afternoon evening)) ==
             %{"night" => 0, "morning" => 0, "afternoon" => 0, "evening" => 0}
  end

  test "seasons preserve raw persisted IANA latitude choice and zero-total contract" do
    stats = [%{"month" => 3, "distance" => 10}, %{"month" => 4, "distance" => 20}]

    assert Patterns.seasons(stats, false) == %{
             "winter" => 0,
             "spring" => 100,
             "summer" => 0,
             "fall" => 0
           }

    assert Patterns.seasons(stats, true) == %{
             "winter" => 0,
             "spring" => 0,
             "summer" => 0,
             "fall" => 100
           }

    assert Patterns.seasons([], true) == %{
             "winter" => 0,
             "spring" => 0,
             "summer" => 0,
             "fall" => 0
           }
  end
end
