defmodule DawarichWeb.StatsFormatTest do
  use ExUnit.Case, async: false

  alias DawarichWeb.{DigestFormat, LocalizedDate, NumberFormat, StatsFormat}

  @corpus "test/fixtures/stats_corpus.json" |> File.read!() |> Jason.decode!()

  test "LocalizedDate matches I18n.l for every corpus date and format in all shipped locales" do
    for %{"locale" => locale, "date" => date, "format" => format, "output" => output} <-
          @corpus["dates"],
        do:
          assert(
            LocalizedDate.l(locale, Date.from_iso8601!(date), format) == output,
            "#{locale} #{date} #{format}"
          )
  end

  test "NumberFormat matches number_with_delimiter and number_with_precision(precision: 1, strip)" do
    for %{"locale" => l, "input" => n, "output" => o} <- @corpus["delimited"],
        do: assert(NumberFormat.delimited(l, n) == o)

    for %{"locale" => l, "input" => x, "output" => o} <- @corpus["precision"],
        do: assert(NumberFormat.precision_one(l, x * 1.0) == o)
  end

  test "the digest helpers match Users::DigestsHelper" do
    for %{"locale" => l, "input" => m, "output" => o} <- @corpus["time_spent"],
        do: assert(DigestFormat.time_spent(l, m) == o, inspect(m))

    for %{"locale" => l, "input" => m, "output" => o} <- @corpus["comparison"],
        do: assert(DigestFormat.comparison_text(l, m) == o, inspect(m))

    for %{"input" => change, "class" => class, "text" => text} <- @corpus["yoy"] do
      assert DigestFormat.yoy_class(change) == class
      assert DigestFormat.yoy_text(change) == text
    end
  end

  test "units: Rails' factors, km by default, an unknown unit raises like DistanceConvertible" do
    assert StatsFormat.unit(%{}) == "km"
    assert StatsFormat.unit(%{"maps" => %{"distance_unit" => "mi"}}) == "mi"
    assert StatsFormat.rounded(38_400, "km") == 38
    assert StatsFormat.rounded(38_400, "mi") == 24
    assert StatsFormat.convert(nil, "km") == 0.0
    assert_raise ArgumentError, fn -> StatsFormat.convert(1, "furlong") end
  end

  test "comparisons follow StatsComparisonHelper, including the zero-average and same-month cases" do
    assert StatsFormat.than_average("en", 12_000, 25) == "52% less than your average this year"
    assert StatsFormat.than_average("en", 38_400, 25) == "54% more than your average this year"
    assert StatsFormat.than_average("en", 25_000, 25) == "0% less than your average this year"
    assert StatsFormat.than_average("en", 12_000, 0) == ""
    march = [[5, 9000], [6, 5400], [7, 14_000], [8, 0]]

    assert StatsFormat.than_previous_active_days("en", march, %{daily: [[1, 1]]}) ==
             "2 days more than previous month"

    assert StatsFormat.than_previous_active_days("en", [[1, 1]], %{daily: [[1, 1], [2, 2]]}) ==
             "1 day less than previous month"

    assert StatsFormat.than_previous_active_days("en", march, nil) == ""
    two = [%{"country" => "A", "cities" => []}, %{"country" => "", "cities" => []}]

    assert StatsFormat.than_previous_countries("en", two, %{toponyms: two}) ==
             "Same as previous month"

    assert StatsFormat.than_previous_countries("de", two, %{toponyms: []}) =~ "2"
  end

  test "peak day, quietest week and the map links follow StatsHelper" do
    march =
      Enum.map(1..31, fn day ->
        [day, Map.get(%{5 => 9000, 6 => 5400, 7 => 14_000, 20 => 10_000}, day, 0)]
      end)

    assert StatsFormat.peak(march) == {7, 14_000}
    assert StatsFormat.peak([[1, 5], [2, 5]]) == {1, 5}
    assert StatsFormat.peak([[1, 0]]) == nil
    assert StatsFormat.peak([]) == nil
    assert StatsFormat.peak_text("en", 2024, 3, {7, 14_000}, "km") == "March 07 (14 km)"
    assert StatsFormat.quietest_week("en", 2024, 3, march) == "Mar 08 - Mar 14"
    assert StatsFormat.quietest_week("en", 2024, 3, []) == "N/A"

    assert StatsFormat.peak_href({"2024-03-07 00:00:00 +0100", "2024-03-07 23:59:59 +0100"}) ==
             "/map/v2?end_at=2024-03-07+23%3A59%3A59+%2B0100&start_at=2024-03-07+00%3A00%3A00+%2B0100"

    assert StatsFormat.year_map_path(2024) ==
             "/map/v2?end_at=2024-12-31T23%3A59&start_at=2024-01-01T00%3A00"
  end

  test "month styling and header colors follow MonthStylingHelper and header_colors" do
    assert {StatsFormat.month_icon(1), StatsFormat.month_icon(4), StatsFormat.month_icon(7),
            StatsFormat.month_icon(10),
            StatsFormat.month_icon(12)} ==
             {"snowflake", "flower", "tree-palm", "leaf", "snowflake"}

    assert StatsFormat.month_color(3) == "#3B945E"

    assert StatsFormat.month_background(3) ==
             "backgrounds/months/ahmad-hasan-xEYWelDHYF0-unsplash.jpg"

    assert StatsFormat.header_color(2024) == "success"

    now = ~U[2026-09-30 10:15:00Z]

    assert StatsFormat.sample_header_color(42, 2024, now) in ~w(info success warning error accent secondary primary)

    previous = Application.get_env(:dawarich, :header_color_picker)
    Application.put_env(:dawarich, :header_color_picker, &List.first/1)

    try do
      assert StatsFormat.sample_header_color(42, 2024, now) == "info"
    after
      if previous,
        do: Application.put_env(:dawarich, :header_color_picker, previous),
        else: Application.delete_env(:dawarich, :header_color_picker)
    end
  end

  test "sample_header_color is a deterministic hash of user, year and UTC hour" do
    now = ~U[2026-09-30 10:15:00Z]
    later_same_hour = ~U[2026-09-30 10:58:00Z]

    colors = for _ <- 1..20, do: StatsFormat.sample_header_color(42, 2024, now)
    assert Enum.uniq(colors) == [hd(colors)]

    assert StatsFormat.sample_header_color(42, 2024, now) ==
             StatsFormat.sample_header_color(42, 2024, later_same_hour)

    hour = div(DateTime.to_unix(now), 3600)
    colors_list = ~w(info success warning error accent secondary primary)

    assert StatsFormat.sample_header_color(42, 2024, now) ==
             Enum.at(colors_list, :erlang.phash2({42, 2024, hour}, 7))
  end

  test "untracked days follow Users::Digest#untracked_days" do
    assert DigestFormat.untracked_days(2024, 43_290) == 335.9
    assert DigestFormat.untracked_days(2023, 0) == 365.0
    assert DigestFormat.untracked_days(2023, 600_000) == 0
  end
end
