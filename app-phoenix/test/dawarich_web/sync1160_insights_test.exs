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

  test "stats requests redirect numeric four-digit years and preserve the native month", %{
    user: user
  } do
    for {path, destination} <- [
          {"/stats", "/insights?year=all"},
          {"/stats/0042", "/insights?year=42"},
          {"/stats/2025", "/insights?year=2025"}
        ] do
      conn = get(NativeAdminUI.conn(user), path)
      assert conn.status == 302
      assert Plug.Conn.get_resp_header(conn, "location") == [destination]
      guest = get(build_conn(), path)
      assert guest.status == 302
      assert URI.parse(hd(Plug.Conn.get_resp_header(guest, "location"))).path == "/users/sign_in"
    end

    for year <- ~w(42 2025tail 20255 abcd) do
      assert get(NativeAdminUI.conn(user), "/stats/" <> year).status == 404
    end

    assert get(NativeAdminUI.conn(user), "/stats/2025/3").status == 200
  end

  test "year route JSON aliases retain scoped data authentication and locked-year privacy", %{
    user: user
  } do
    for path <- ["/insights/routes/2025", "/insights/routes/2025.json"] do
      conn =
        NativeAdminUI.conn(user)
        |> Plug.Conn.put_req_header("accept", "application/json")
        |> get(path)

      assert conn.status == 200

      assert Plug.Conn.get_resp_header(conn, "content-type") == [
               "application/json; charset=utf-8"
             ]

      assert Plug.Conn.get_resp_header(conn, "cache-control") == ["private, no-store"]
      assert %{"lines" => [_ | _]} = Jason.decode!(conn.resp_body)
      guest = build_conn() |> Plug.Conn.put_req_header("accept", "application/json") |> get(path)
      assert guest.status == 302
      assert URI.parse(hd(Plug.Conn.get_resp_header(guest, "location"))).path == "/users/sign_in"
    end

    System.put_env("SELF_HOSTED", "false")
    Dawarich.Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [user.id], log: false)
    conn = get(NativeAdminUI.conn(user), "/insights/routes/2018.json")
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == %{"lines" => []}
  end

  test "self-hosted Lite preview admission uses the configured mode while Cloud keeps its window",
       %{user: user} do
    Dawarich.Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [user.id], log: false)
    System.put_env("SELF_HOSTED", "true")
    own = get(NativeAdminUI.conn(user), "/insights/routes/2018.json")
    assert own.status == 200
    assert %{"lines" => [_ | _]} = Jason.decode!(own.resp_body)
    System.put_env("SELF_HOSTED", "false")
    cloud = get(NativeAdminUI.conn(user), "/insights/routes/2018.json")
    assert cloud.status == 200
    assert Jason.decode!(cloud.resp_body) == %{"lines" => []}
  end

  test "consolidated insights offers tracked counts country lists newest six previews and twelve months",
       %{user: user} do
    {:ok, view, html} = live(NativeAdminUI.conn(user), "/insights?year=all")
    assert has_element?(view, "#native-insights-tracking")
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
    assert has_element?(view, "[data-testid=country-ribbon]", "France")

    assert Enum.count(
             LazyHTML.query(
               LazyHTML.from_document(render(view)),
               "[data-testid=country-ribbon-lane]"
             )
           ) == 8

    assert has_element?(view, "[data-testid=country-ribbon]", "+2 more countries")
    assert has_element?(view, "[data-testid=distance-race]")
    render_click(view, "calendar_mode", %{"mode" => "countries"})
    assert has_element?(view, "[data-testid=year-calendar] .year-calendar[data-mode=countries]")
    render_click(view, "calendar_country", %{"country" => "France"})
    assert has_element?(view, "[data-testid=year-calendar] .year-calendar[data-focus=France]")
    render_patch(view, "/insights?year=2024")
    render_async(view)
    refute has_element?(view, "[data-testid=year-calendar] .year-calendar[data-focus=France]")
  end

  test "calendar distinguishes distance intensity and preserves country-only mode", %{user: user} do
    stat!(user.id, %{
      year: 2025,
      month: 4,
      distance: 76_000,
      daily_distance: [[1, 1000], [2, 5000], [3, 10_000], [4, 20_000], [5, 40_000]],
      toponyms: [toponym("France", [])]
    })

    Dawarich.Test.FrameSeeds.point!(
      user.id,
      916_296,
      DateTime.to_unix(~U[2025-04-01 12:00:00Z]),
      %{country_name: "France"}
    )

    Dawarich.Test.FrameSeeds.point!(
      user.id,
      916_295,
      DateTime.to_unix(~U[2025-04-07 12:00:00Z]),
      %{country_name: "France"}
    )

    {:ok, view, _} = live(NativeAdminUI.conn(user), "/insights?year=2025")
    render_async(view)

    for mode <- ~w(both distance) do
      render_click(view, "calendar_mode", %{"mode" => mode})

      assert has_element?(view, ".year-calendar[data-mode='#{mode}']")

      for {day, alpha} <- [{1, "0.32"}, {3, "0.5"}, {4, "0.72"}, {5, "1"}, {6, "0.32"}] do
        selector = "[data-date='2025-04-0#{day}']"

        [style] =
          view
          |> render()
          |> LazyHTML.from_document()
          |> LazyHTML.query(selector)
          |> LazyHTML.attribute("style")

        assert String.ends_with?(style, "--a: " <> alpha)
      end

      assert has_element?(
               view,
               "[data-date='2025-04-07'][data-country=France]:not([data-distance])"
             )
    end

    render_click(view, "calendar_mode", %{"mode" => "countries"})

    assert has_element?(
             view,
             ".year-calendar[data-mode=countries] [data-date='2025-04-01'][data-country=France]"
           )

    assert has_element?(view, "[data-date='2025-04-05']:not([data-country])[data-distance]")
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
