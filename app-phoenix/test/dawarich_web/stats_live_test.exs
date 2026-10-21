defmodule DawarichWeb.StatsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.Test.RailsUser

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})

    user =
      RailsUser.insert!(%{
        id: 5301,
        email: "a5s-live@dawarich.test",
        settings: %{"timezone" => "Europe/Berlin", "maps" => %{"distance_unit" => "km"}}
      })

    %{user: user}
  end

  defp live_as(user, path, opts \\ []),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path, opts)

  describe "routes" do
    test "each page mounts for a signed-in user with Rails' title", %{user: user} do
      for {path, title} <- [
            {"/insights?year=all", "Insights | Dawarich"},
            {"/insights?year=2024", "Insights | Dawarich"},
            {"/stats/2024/03", "March 2024 Monthly Digest | Dawarich"},
            {"/digests", "Year-End Digests | Dawarich"}
          ] do
        {:ok, _view, html} = live_as(user, path)
        assert html =~ ">#{title}</title>", path
      end
    end
  end

  describe "Rails assets" do
    setup do
      :persistent_term.put({DawarichWeb.Assets, :rails_imports}, %{
        "chartkick" => "/assets/chartkick-0123abcd.js",
        "app" => "/assets/should-not-win.js"
      })

      on_exit(fn -> :persistent_term.erase({DawarichWeb.Assets, :rails_imports}) end)
    end

    test "native monthly charts retain their feature entry without loading Rails imports", %{
      user: user
    } do
      html = RailsUser.signed_in(user.id) |> get("/stats/2024/03") |> html_response(200)
      refute String.contains?(html, "importmap")
      refute String.contains?(html, "i18n-translations")
      refute String.contains?(html, "Chartkick")
      assert String.contains?(html, "/native/app.js")
      refute String.contains?(html, "should-not-win")
    end

    test "native trip cards retain their entry without loading Rails imports", %{user: user} do
      html = RailsUser.signed_in(user.id) |> get("/trips") |> html_response(200)
      refute String.contains?(html, "importmap")
      refute String.contains?(html, "i18n-translations")
      refute String.contains?(html, "Chartkick")
      assert String.contains?(html, "/native/app.js")
    end

    test "rails_charts: false keeps Rails' modules and drops Chartkick" do
      root = fn extra ->
        render_component(
          &DawarichWeb.Layouts.root/1,
          Map.merge(
            %{
              locale: "en",
              current_user: nil,
              self_hosted: true,
              page_title: nil,
              rails_csrf_token: nil,
              rails_js: true,
              inner_content: ""
            },
            extra
          )
        )
      end

      assert root.(%{}) =~ "/native/app.js"
      html = root.(%{rails_charts: false})
      assert html =~ "/native/app.js"
      refute html =~ "importmap"
      refute html =~ ~r/import "chartkick"/
    end

    test "native monthly commands refuse arbitrary browser flash injection", %{user: user} do
      {:ok, view, _html} = live_as(user, "/stats/2024/03")
      render_hook(view, "rails_flash", %{"type" => "success", "message" => "untrusted-flash"})
      refute has_element?(view, "[role=alert]", "untrusted-flash")
      assert has_element?(view, "[role=alert]")
    end
  end

  describe "stats pages" do
    import Dawarich.Test.StatsSeeds

    setup %{user: user} do
      for key <-
            ~w(PHOTON_API_HOST GEOAPIFY_API_KEY NOMINATIM_API_HOST LOCATIONIQ_API_KEY STORE_GEODATA SELF_HOSTED),
          do: System.delete_env(key)

      Dawarich.FixtureCleanup.delete!(Dawarich.ScratchRepo, ~w(phoenix.stats_point_counts))

      Dawarich.ScratchRepo.query!(
        "INSERT INTO phoenix.stats_point_counts VALUES ($1, 77, 1, now())",
        [user.id],
        log: false
      )

      Dawarich.Repo.query!(
        "UPDATE users SET points_count = 77, api_key = 'a5s-live-key' WHERE id = $1",
        [user.id]
      )

      Dawarich.Repo.query!(
        "INSERT INTO phoenix.stats_point_counts (user_id,geocoded,without_data,computed_at) VALUES ($1,77,1,now()) ON CONFLICT (user_id) DO UPDATE SET geocoded=77,without_data=1,computed_at=now()",
        [user.id],
        log: false
      )

      geocoding!()
      stamp = ~N[2026-01-01 00:00:00]

      Dawarich.Repo.insert_all(
        "countries",
        for(
          {name, code} <- [{"Germany", "DE"}, {"Czechia", "CZ"}],
          do: %{name: name, iso_a2: code, iso_a3: code, created_at: stamp, updated_at: stamp}
        )
      )

      march =
        for day <- 1..31,
            do: [day, Map.get(%{5 => 9000, 6 => 5400, 7 => 14_000, 20 => 10_000}, day, 0)]

      april = for day <- 1..30, do: [day, if(day == 10, do: 12_000, else: 0)]

      stat!(user.id, %{
        year: 2024,
        month: 3,
        distance: 38_400,
        daily_distance: march,
        toponyms: [toponym("Germany", ["Berlin"]), toponym("Czechia", ["Prague"])],
        updated_at: ~N[2024-04-01 10:00:00]
      })

      stat!(user.id, %{
        year: 2024,
        month: 4,
        distance: 12_000,
        daily_distance: april,
        toponyms: [toponym("Germany", ["Berlin"])],
        updated_at: ~N[2024-05-01 10:00:00]
      })

      stat!(user.id, %{
        year: 2023,
        month: 7,
        distance: 20_000,
        toponyms: [toponym("Germany", ["Berlin"])]
      })

      :ok
    end

    defp texts(html, selector),
      do:
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query(selector)
        |> Enum.map(&LazyHTML.text/1)
        |> Enum.reject(&(&1 == ""))

    test "stats summaries and year cards remain locale and unit correct without Rails fragments",
         %{user: user} do
      for {unit, total} <- [{"km", "70"}, {"mi", "44"}], locale <- ~w(en de) do
        Dawarich.Repo.query!(
          "UPDATE users SET settings=jsonb_set(settings,'{maps,distance_unit}',$1::jsonb) WHERE id=$2",
          [unit, user.id]
        )

        html =
          RailsUser.signed_in(user.id)
          |> get("/insights?year=all&locale=#{locale}")
          |> html_response(200)

        assert Enum.take(Enum.map(texts(html, ".card-body > .text-3xl"), &String.trim/1), 1) == [
                 "#{total} #{unit}"
               ]

        assert texts(html, "[data-testid=insights-year-card] h3 > a") == ["2024", "2023"]
        cards = if unit == "km", do: ["50 km", "20 km"], else: ["31 mi", "12 mi"]

        assert Enum.map(
                 texts(
                   html,
                   "[data-testid=insights-year-card] .text-lg.font-semibold.tabular-nums"
                 ),
                 &String.trim/1
               ) ==
                 cards

        assert html =~ DawarichWeb.Translate.t(locale, "insights.index.insights", %{})
      end
    end

    test "native index retains source totals ready counts and one card per year", %{user: user} do
      {:ok, view, html} = live_as(user, "/insights?year=all")
      assert html =~ ">Insights | Dawarich</title>"
      assert has_element?(view, ".card-body > .text-3xl", "70 km")
      assert :sys.get_state(view.pid).socket.assigns.data.consolidated.index.points.total == 77

      assert :sys.get_state(view.pid).socket.assigns.data.consolidated.index.points.percentage ==
               100

      assert has_element?(view, "#native-insights-tracking", "1 points without data")
      assert has_element?(view, "#insights-update", "Update stats")
      assert texts(html, "[data-testid=insights-year-card] h3 > a") == ["2024", "2023"]

      assert has_element?(
               view,
               "[data-testid=insights-year-card] label[for]",
               "2 countries, 2 cities"
             )

      assert has_element?(
               view,
               "[data-testid=insights-year-card] label[for]",
               "1 countries, 1 cities"
             )

      refute html =~ "data-turbo-method"
    end

    test "native place dialogs switch source countries and cities without losing totals", %{
      user: user
    } do
      {:ok, view, _} = live_as(user, "/insights?year=all")
      view |> element("button[phx-value-kind=countries]") |> render_click()
      assert texts(render(view), "#stats-dialog li") == ["Czechia", "Germany"]
      render_click(view, "close_dialog", %{})
      view |> element("button[phx-value-kind=cities]") |> render_click()
      assert texts(render(view), "#stats-dialog li") == ["Berlin", "Prague"]
      render_click(view, "close_dialog", %{})
      assert has_element?(view, ".card-body > .text-3xl", "70 km")
      refute has_element?(view, "#stats-dialog")
    end

    test "native charts update only their plot island and retain source accessible values", %{
      user: user
    } do
      {:ok, view, html} = live_as(user, "/insights?year=all")

      strips =
        html |> LazyHTML.from_document() |> LazyHTML.query("[data-testid=insights-year-strip]")

      assert Enum.count(strips) == 2
      assert has_element?(view, "[data-testid=insights-year-strip][role=img][aria-label]")

      [year | _] =
        strips |> Enum.map(&(LazyHTML.query(&1, "span") |> LazyHTML.attribute("title")))

      assert Enum.slice(year, 2, 2) == ["March: 38 km", "April: 12 km"]
      refute html =~ "RailsStimulus"
      refute has_element?(view, "[data-testid=insights-year-card][phx-update=ignore]")
    end

    test "native year chart cards and links retain source window values", %{user: user} do
      {:ok, view, html} = live_as(user, "/insights?year=2024")
      assert html =~ ">Insights | Dawarich</title>"
      assert has_element?(view, "a[href='/stats/2024/3']", "March")
      render_async(view)

      {:ok, year_data} =
        Dawarich.Stats.Pages.year(
          Dawarich.Accounts.Scope.for_user(user, "en"),
          %{"year" => "2024"},
          self_hosted: true
        )

      assert Enum.any?(year_data.stats, &String.contains?(inspect(&1.toponyms), "Berlin"))
      assert Enum.any?(year_data.stats, &String.contains?(inspect(&1.toponyms), "Prague"))

      assert :sys.get_state(view.pid).socket.assigns.data.consolidated.months
             |> Enum.map(& &1.distance)
             |> Enum.sum() == 50400

      assert has_element?(view, "[data-testid=insights-month]")
    end

    test "a month without a stat is Rails' empty state with HTTP 200", %{user: user} do
      html = RailsUser.signed_in(user.id) |> get("/stats/2024/2") |> html_response(200)
      assert html =~ ">February 2024 Monthly Digest | Dawarich</title>"

      assert texts(html, ".alert") |> Enum.join() =~
               "No location data available for this month"

      refute html =~ "stat-page-card"
    end

    test "a month compares itself with the year's average and the previous month", %{user: user} do
      {:ok, view, _html} = live_as(user, "/stats/2024/4")
      assert has_element?(view, "#native-stats-month-distance", "~12 km")
      assert has_element?(view, ".stat-desc", "52% less than your average this year")
      assert has_element?(view, "#native-stats-month-active-days", "1/30")
      assert has_element?(view, ".stat-desc", "3 days less than previous month")
      assert has_element?(view, ".stat-desc", "1 country less than previous month")
    end

    test "the peak day links to the map with the user's zoned day bounds", %{user: user} do
      {:ok, view, _html} = live_as(user, "/stats/2024/3")

      href =
        "/map/v2?end_at=2024-03-07+23%3A59%3A59+%2B0100&start_at=2024-03-07+00%3A00%3A00+%2B0100"

      assert has_element?(view, "#native-stats-peak-day", "March 07 (14 km)")

      [actual] =
        view
        |> render()
        |> LazyHTML.from_document()
        |> LazyHTML.query("#native-stats-peak-day")
        |> LazyHTML.attribute("href")

      assert URI.decode_query(URI.parse(actual).query) == URI.decode_query(URI.parse(href).query)
      assert render(view) =~ "Mar 08 - Mar 14"
      assert has_element?(view, ~s(a.btn[href="/insights?year=2024"]), "← Back to 2024")
    end

    test "the API key never becomes a bare socket assign that a crash report would dump in clear",
         %{user: user} do
      current_user = Dawarich.Accounts.get(user.id)
      assert current_user.api_key == "a5s-live-key"

      context = %{
        locale: "en",
        now: DateTime.utc_now(),
        self_hosted: true,
        base_url: "http://www.example.com"
      }

      assigns =
        DawarichWeb.StatsLive.Month.page(
          current_user,
          %{"year" => "2024", "month" => "3"},
          context
        )

      refute Map.has_key?(assigns, :api_key)
    end

    test "native monthly map and sharing use the scoped hosts without a DOM credential", %{
      user: user
    } do
      {:ok, view, html} = live_as(user, "/stats/2024/3")
      assert has_element?(view, "[phx-hook=MapPreview]")
      refute String.contains?(html, "a5s-live-key")
      assert has_element?(view, "button[phx-click=open_share]")
      render_click(view, "open_share", %{})
      assert has_element?(view, "#stats-sharing")
      refute has_element?(view, "#sharing_modal")
    end

    test "a Lite user on Cloud sees the data window alert, a locked year and the sharing upgrade prompt",
         %{user: user} do
      System.put_env("SELF_HOSTED", "false")
      System.put_env("JWT_SECRET_KEY", "phoenix-a5-jwt-fixture-secret-not-for-production")
      on_exit(fn -> for key <- ~w(SELF_HOSTED JWT_SECRET_KEY), do: System.delete_env(key) end)
      Dawarich.Repo.query!("UPDATE users SET plan = 0 WHERE id = $1", [user.id])
      today = Date.utc_today()

      stat!(user.id, %{
        year: today.year,
        month: today.month,
        distance: 1000,
        daily_distance: [[1, 1000]]
      })

      {:ok, view, _html} = live_as(user, "/insights?year=all")

      assert has_element?(view, "#native-insights-window-alert[role=alert]")
      assert has_element?(view, "[data-testid=insights-locked-year]", "2023")
      assert has_element?(view, "a[phx-click=upgrade]")
      {:ok, month, _html} = live_as(user, "/stats/#{today.year}/#{today.month}")
      assert has_element?(month, "button[phx-click=open_share]")
      assert has_element?(month, ".alert-info[role=alert]")
      refute has_element?(month, "#sharing_modal")
    end
  end
end
