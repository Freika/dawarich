defmodule Dawarich.Sync1160I18nTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]
  alias Dawarich.I18n

  test "seven source locales export every sync key without fallback and interpolate real bindings" do
    groups = [
      {"devise.registrations.new.steps",
       ~w(account.title account.body import.title import.body mobile_app.title mobile_app.body)},
      {"devise.sessions.new.benefits",
       ~w(import.title import.body map.title map.body privacy.title privacy.body stats.title stats.body)},
      {"insights.country_ribbon", ~w(title today segment more_countries)},
      {"insights.distance_race",
       ~w(ahead aria behind by_date ended_at no_previous same_day so_far title title_single)},
      {"insights", ~w(header.period months.title year_cards.title)},
      {"insights.year_calendar",
       ~w(mode mode_both mode_countries mode_distance no_data timezone_note)},
      {"map.maplibre.button_cluster", ~w(family family_f tools tools_c)},
      {"map.maplibre.settings_panel", ~w(manage_family)},
      {"javascript.map_panel", ~w(family)},
      {"supporter_platforms", ~w(app_store)},
      {"controllers.settings.users", ~w(cannot_delete_yourself_or_last_admin)},
      {"trips.filters",
       ~w(all_countries all_months all_years apply choose_year_first country month reset search search_placeholder sort year sorts.distance sorts.name sorts.newest sorts.oldest)},
      {"trips.index", ~w(no_matching_trips show_all_trips try_other_filters)}
    ]

    bindings = %{
      "year" => 2026,
      "previous" => 2025,
      "distance" => "12",
      "unit" => "km",
      "date" => "2026-10-16",
      "count" => 2,
      "zone" => "Europe/Berlin",
      "country" => "Germany",
      "days" => 2,
      "from" => "2026-01-01",
      "to" => "2026-01-03"
    }

    for locale <- ~w(en ca de es fr pl zh), {prefix, leaves} <- groups, leaf <- leaves do
      assert {:ok, value} = I18n.t(locale, prefix <> "." <> leaf, bindings, fallback: false)
      assert is_binary(value)
      refute value =~ "%{"
    end

    for locale <- ~w(en ca de es fr pl zh) do
      {:ok, label} = I18n.t(locale, "supporter_platforms.app_store", %{}, fallback: false)

      html =
        render_component(&DawarichWeb.Components.SupporterCard.card/1,
          user: %{settings: %{}},
          locale: locale,
          supporter: true,
          platform: "app_store"
        )

      assert html |> LazyHTML.from_fragment() |> LazyHTML.text() |> String.contains?(label)
      refute html =~ "translation_missing"
    end
  end

  test "Polish ribbon preserves the Rails simple backend zero one and other contract" do
    for {count, expected} <- [
          {0, "+0 kraju więcej"},
          {1, "+1 kraj więcej"},
          {2, "+2 kraju więcej"},
          {5, "+5 kraju więcej"},
          {22, "+22 kraju więcej"}
        ] do
      assert I18n.t("pl", "insights.country_ribbon.more_countries", %{"count" => count},
               fallback: false
             ) == {:ok, expected}
    end
  end
end
