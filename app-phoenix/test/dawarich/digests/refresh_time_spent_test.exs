defmodule Dawarich.Digests.RefreshTimeSpentTest do
  use ExUnit.Case, async: true
  alias Dawarich.Digests.Refresh.TimeSpent

  test "single country gets a day, multi-country spans use Ruby rounded proportions" do
    rows = [
      [~D[2024-03-01], "Germany", 0, 0],
      [~D[2024-03-02], "Germany", 0, 60],
      [~D[2024-03-02], "Czechia", 120, 240],
      [~D[2024-03-03], "Czechia", 0, 0],
      [~D[2024-03-03], "Austria", 0, 0]
    ]

    assert TimeSpent.countries(rows) == [{"Germany", 1920}, {"Czechia", 1680}, {"Austria", 720}]
  end

  test "city ties retain first source appearance and total country minutes include beyond top10" do
    countries = for n <- 1..11, do: {"country#{n}", 1440}

    stats = [
      %{
        "toponyms" => [
          %{
            "cities" => [
              %{"city" => "Z", "stayed_for" => "60x"},
              %{"city" => "A", "stayed_for" => 60}
            ]
          }
        ]
      }
    ]

    result = TimeSpent.compose(countries, stats)
    assert result["total_country_minutes"] == 11 * 1440
    assert length(result["countries"]) == 10

    assert result["cities"] == [
             %{"name" => "Z", "minutes" => 60},
             %{"name" => "A", "minutes" => 60}
           ]
  end
end
