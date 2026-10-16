defmodule DawarichWeb.Sync1160InsightsTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.StatsSeeds
  alias Dawarich.Test.NativeAdminUI
  @endpoint DawarichWeb.Endpoint

  setup do
    %{target: user} = NativeAdminUI.setup!()

    for year <- 2018..2025 do
      stat!(user.id, %{
        year: year,
        month: 3,
        distance: 1000,
        daily_distance: [[1, 1000]],
        toponyms: [toponym("France", [])]
      })

      Dawarich.Test.FrameSeeds.track!(user.id, 916_200 + year, %{
        start_at: NaiveDateTime.new!(year, 3, 1, 12, 0, 0),
        end_at: NaiveDateTime.new!(year, 3, 1, 13, 0, 0)
      })
    end

    %{user: user}
  end

  test "consolidated insights offers tracked counts country lists newest six previews and twelve months",
       %{user: user} do
    {:ok, view, html} = live(NativeAdminUI.conn(user), "/insights?year=all")
    assert has_element?(view, "#insights-tracking")
    assert has_element?(view, "[data-testid=insights-year-card]", "2025")

    assert Enum.count(
             LazyHTML.query(LazyHTML.from_document(html), "[data-testid=insights-year-map]")
           ) == 6

    render_click(view, "open_places", %{"kind" => "countries"})
    assert has_element?(view, "[role=dialog]", "France")
    render_click(view, "close_dialog", %{})
    render_patch(view, "/insights?year=2025")

    assert Enum.count(
             LazyHTML.query(LazyHTML.from_document(render(view)), "[data-testid=insights-month]")
           ) == 12

    assert has_element?(view, "a[href='/stats/2025/3']")
    assert has_element?(view, "[data-testid=insights-month][data-empty=true]", "January")
    render_patch(view, "/insights?year=2020")
    assert has_element?(view, "[data-testid=insights-month]", "March")
  end

  test "native calendar modes focus UTC country days and race survive period changes", %{
    user: user
  } do
    Dawarich.Test.FrameSeeds.point!(
      user.id,
      916_299,
      DateTime.to_unix(~U[2025-03-01 12:00:00Z]),
      %{country_name: "France"}
    )

    Dawarich.Test.FrameSeeds.point!(
      user.id,
      916_297,
      DateTime.to_unix(~U[2025-03-02 12:00:00Z]),
      %{country_name: "France"}
    )

    for n <- 1..9 do
      Dawarich.Test.FrameSeeds.point!(
        user.id,
        920_000 + n,
        DateTime.to_unix(~U[2025-03-01 13:00:00Z]) + n,
        %{country_name: "Country #{n}"}
      )
    end

    {:ok, view, _} = live(NativeAdminUI.conn(user), "/insights?year=2025")
    render_async(view)
    assert has_element?(view, "[data-testid=year-calendar]")
    assert has_element?(view, "[data-testid=country-ribbon-lane]", "France")

    assert Enum.count(
             LazyHTML.query(
               LazyHTML.from_document(render(view)),
               "[data-testid=country-ribbon-lane]"
             )
           ) == 8

    assert has_element?(view, "[data-testid=country-ribbon]", "+2 more countries")
    assert has_element?(view, "[data-testid=distance-race]")
    render_click(view, "calendar_mode", %{"mode" => "countries"})
    assert has_element?(view, "[data-testid=year-calendar][data-mode=countries]")
    render_click(view, "calendar_country", %{"country" => "France"})
    assert has_element?(view, "[data-testid=year-calendar][data-country=France]")
    render_patch(view, "/insights?year=2024")
    render_async(view)
    refute has_element?(view, "[data-testid=year-calendar][data-country=France]")
  end

  test "recalculation commands return the corresponding consolidated insights period", %{
    user: user
  } do
    conn = %{Plug.Test.conn(:get, "/stats/0042") | path_params: %{"year" => "0042"}}
    response = DawarichWeb.InsightsRedirect.call(conn, :year)
    assert Plug.Conn.get_resp_header(response, "location") == ["/insights?year=42"]
    context = %{now: DateTime.utc_now(), locale: "en"}

    assert {:ok, %{path: "/insights?year=2025"}} =
             Dawarich.Stats.WebCommands.update(Dawarich.Repo, user, "2025", "all", context)

    assert {:ok, %{path: "/insights?year=all"}} =
             Dawarich.Stats.WebCommands.update_all(Dawarich.Repo, user, context)
  end

  test "calendar events recheck a lapsed data window before revealing country details", %{
    user: user
  } do
    previous = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", "synthetic-analytics-test-key")

    on_exit(fn ->
      if previous,
        do: System.put_env("JWT_SECRET_KEY", previous),
        else: System.delete_env("JWT_SECRET_KEY")
    end)

    System.put_env("SELF_HOSTED", "false")
    Dawarich.Repo.query!("UPDATE users SET plan=1 WHERE id=$1", [user.id], log: false)

    Dawarich.Test.FrameSeeds.point!(
      user.id,
      916_298,
      DateTime.to_unix(~U[2025-03-01 12:00:00Z]),
      %{country_name: "France"}
    )

    {:ok, view, _} = live(NativeAdminUI.conn(user), "/insights?year=2025")
    render_async(view)
    assert has_element?(view, "[data-testid=year-calendar]")
    Dawarich.Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [user.id], log: false)
    render_click(view, "calendar_mode", %{"mode" => "countries"})
    refute has_element?(view, "[data-testid=year-calendar]")
    refute has_element?(view, "a[href='/stats/2025/3']")
  end

  test "race labels resolve year date distance and units in every supported locale" do
    rows = [
      %{year: 2025, month: 1, daily_distance: [[1, 1000]]},
      %{year: 2024, month: 1, daily_distance: [[1, 1000]]}
    ]

    for locale <- ~w(en ca de es fr pl zh), history <- [rows, Enum.take(rows, 1)] do
      race = Dawarich.Insights.DistanceRace.build(history, 2025, ~D[2025-01-01])

      html =
        render_component(&DawarichWeb.InsightsLive.NativeRace.render/1,
          race: race,
          locale: locale,
          unit: "km",
          today: ~D[2025-01-01]
        )

      assert Enum.empty?(LazyHTML.query(LazyHTML.from_document(html), ".translation_missing")),
             locale

      refute String.contains?(html, "%{"), locale
      assert String.contains?(html, "km"), locale
    end
  end
end
