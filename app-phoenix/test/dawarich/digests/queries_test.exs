defmodule Dawarich.Digests.QueriesTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.DigestFixtures
  alias Dawarich.Digests.{Context, Queries}

  test "yearly aggregate uses scoped months but first visits and comparisons retain full history" do
    kase = DigestFixtures.case!("lite_partial_yearly")
    DigestFixtures.load!(ScratchRepo, kase)
    context = Context.load!(ScratchRepo, 14101, DigestFixtures.options(kase))
    months = Queries.yearly(ScratchRepo, context, 2025)
    history = Queries.history(ScratchRepo, context)

    assert Enum.map(months, & &1["month"]) == [10, 12]
    assert Enum.all?(months, &(&1["user_id"] == 14101))

    assert Enum.find(history, &(&1["id"] == 14305))["toponyms"] == [
             %{"country" => "Germany", "cities" => [%{"city" => "Berlin"}]}
           ]

    assert length(history) == 5
    assert Enum.find(history, &(&1["id"] == 14301))["year"] == 2024

    assert Queries.monthly(ScratchRepo, context, 2025, 1)["distance"] == 7777

    assert Queries.monthly(ScratchRepo, context, 2025, 10)["daily_distance"] == [
             [1, 12.5],
             ["2", "24"],
             [3, 0]
           ]

    assert Queries.monthly(ScratchRepo, context, 2022, 1) == nil
    assert Queries.distance(ScratchRepo, context) == "25000"
  end
end
