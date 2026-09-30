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
            {"/stats", "Statistics | Dawarich"},
            {"/stats/2024", "Statistics for 2024 year | Dawarich"},
            {"/stats/2024/03", "March 2024 Monthly Digest | Dawarich"},
            {"/digests", "Year-End Digests | Dawarich"}
          ] do
        {:ok, _view, html} = live_as(user, path)
        assert html =~ "<title>#{title}</title>", path
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

    test "a rails_js page loads Rails' imports, translations and Chartkick; Phoenix's own entries win",
         %{user: user} do
      html = RailsUser.signed_in(user.id) |> get("/stats") |> html_response(200)
      head = html |> LazyHTML.from_document() |> LazyHTML.query("head")

      imports =
        head
        |> LazyHTML.query("script[type='importmap']")
        |> LazyHTML.text()
        |> Jason.decode!()
        |> Map.fetch!("imports")

      assert imports["chartkick"] == "/assets/chartkick-0123abcd.js"
      assert imports["app"] =~ "/phoenix/js/app.js?vsn="

      translations =
        head
        |> LazyHTML.query("script#i18n-translations[type='application/json']")
        |> LazyHTML.text()
        |> Jason.decode!()

      assert translations["stats"]["map_initialization_failed"] == "Failed to initialize map"
      assert Map.has_key?(translations, "transportation_modes")
      assert html =~ ~r/import "chartkick"\s+import "Chart.bundle"/
    end

    test "a page without rails_js keeps slice 1's head", %{user: user} do
      html = RailsUser.signed_in(user.id) |> get("/notifications") |> html_response(200)
      refute html =~ "i18n-translations"
      refute html =~ "chartkick"
    end

    test "rails_flash shows only success and error flashes", %{user: user} do
      {:ok, view, _html} = live_as(user, "/stats")

      refute render_hook(view, "rails_flash", %{
               "type" => "info",
               "message" => "a5s-unwanted-flash"
             }) =~ "a5s-unwanted-flash"

      html = render_hook(view, "rails_flash", %{"type" => "success", "message" => "Auto-saved"})
      assert html =~ "alert-success"
      assert html =~ "Auto-saved"
    end
  end

  describe "stats pages" do
    import Dawarich.Test.StatsSeeds

    setup %{user: user} do
      for key <-
            ~w(PHOTON_API_HOST GEOAPIFY_API_KEY NOMINATIM_API_HOST LOCATIONIQ_API_KEY STORE_GEODATA SELF_HOSTED),
          do: System.delete_env(key)

      Dawarich.ScratchRepo.query!("TRUNCATE phoenix.stats_point_counts", [], log: false)

      Dawarich.ScratchRepo.query!(
        "INSERT INTO phoenix.stats_point_counts VALUES ($1, 77, 1, now())",
        [user.id],
        log: false
      )

      Dawarich.Repo.query!(
        "UPDATE users SET points_count = 77, api_key = 'a5s-live-key' WHERE id = $1",
        [user.id]
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

    test "the index: Rails' totals, method links, one card per year", %{user: user} do
      {:ok, view, html} = live_as(user, "/stats", on_error: [duplicate_id: :warn])
      assert html =~ "<title>Statistics | Dawarich</title>"
      assert has_element?(view, ".stat-value.text-primary", "70 km")
      assert has_element?(view, ".stat-value.text-success", "77")
      assert has_element?(view, ".stat-desc", "100% of all points")
      assert has_element?(view, ".stat-title .tooltip", "1 points without data")

      assert has_element?(
               view,
               ~s(a[href="/stats/update_all"][data-turbo-method="put"]),
               "Update stats"
             )

      assert has_element?(view, ~s(a[href="/stats/2024/all/update"][data-turbo-method="put"]))
      assert has_element?(view, ~s(a.btn[href="/digests"]), "Year-End Digests")
      assert texts(html, "h2.card-title > div > a:first-child") == ["2024", "2023"]
      assert has_element?(view, "a.link-primary", "2 countries, 2 cities")
      assert has_element?(view, "a.link-primary", "1 countries, 1 cities")
    end

    test "the nodes stats-index.spec.js matches with anchored regexes carry no surrounding whitespace",
         %{user: user} do
      html = RailsUser.signed_in(user.id) |> get("/stats") |> html_response(200)
      assert texts(html, "#countries_visited p") == ["Czechia", "Germany"]
      assert texts(html, "#cities_visited p") == ["Berlin", "Prague"]
      assert texts(html, "#countries_cities_modal_2024 + .modal .text-sm") == ["Prague", "Berlin"]
    end

    test "every element the browser changes is an ignored island with an id", %{user: user} do
      {:ok, view, _html} = live_as(user, "/stats", on_error: [duplicate_id: :warn])

      for selector <-
            ~w(#chart-year-distance-2024 #chart-year-distance-2023 #countries_visited #cities_visited #countries_cities_modal_2024),
          do: assert(has_element?(view, selector <> "[phx-update='ignore']"), selector)
    end

    test "the year page: the chart over the year, the cards in the window, Rails' relative hrefs",
         %{user: user} do
      {:ok, view, html} = live_as(user, "/stats/2024")
      assert html =~ "<title>Statistics for 2024 year | Dawarich</title>"
      assert has_element?(view, ~s(a[href="2024/3"]), "March 2024")

      assert has_element?(
               view,
               ~s(a[href="2024/3"] .text-sm.text-gray-600),
               "2 countries, 2 cities"
             )

      assert has_element?(view, ~s(a[href="2024/4"]), "12")
      assert has_element?(view, "#chart-year-distance-2024[phx-update='ignore']")
    end

    test "a month without a stat is Rails' empty state with HTTP 200", %{user: user} do
      html = RailsUser.signed_in(user.id) |> get("/stats/2024/2") |> html_response(200)
      assert html =~ "<title>February 2024 Monthly Digest | Dawarich</title>"
      assert html =~ ~s(<div class="alert">No location data available for this month</div>)
      refute html =~ "stat-page-card"
    end

    test "a month compares itself with the year's average and the previous month", %{user: user} do
      {:ok, view, _html} = live_as(user, "/stats/2024/4")
      assert has_element?(view, ".stat-value.text-success", "~12 km")
      assert has_element?(view, ".stat-desc", "52% less than your average this year")
      assert has_element?(view, ".stat-value.text-secondary", "1/30")
      assert has_element?(view, ".stat-desc", "3 days less than previous month")
      assert has_element?(view, ".stat-desc", "1 country less than previous month")
    end

    test "the peak day links to the map with the user's zoned day bounds", %{user: user} do
      {:ok, view, _html} = live_as(user, "/stats/2024/3")

      href =
        "/map/v2?end_at=2024-03-07+23%3A59%3A59+%2B0100&start_at=2024-03-07+00%3A00%3A00+%2B0100"

      assert has_element?(view, ~s(a.underline[href="#{href}"]), "March 07 (14 km)")
      assert render(view) =~ "Mar 08 - Mar 14"
      assert has_element?(view, ~s(a.btn[href="/stats/2024"]), "← Back to 2024")
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

    test "the map card and the sharing dialog are hooked islands with Rails' Stimulus attributes",
         %{user: user} do
      {:ok, view, _html} = live_as(user, "/stats/2024/3")

      assert has_element?(
               view,
               ~s(#stat-page-card[phx-hook="RailsStimulus"][phx-update="ignore"][data-controller="stat-page"][data-api-key="a5s-live-key"][data-year="2024"][data-month="3"][data-tiles-url=""][data-tiles-fallback="false"])
             )

      assert has_element?(
               view,
               ~s(#stat-page-card #monthly-stats-map[data-stat-page-target="map"])
             )

      assert has_element?(
               view,
               ~s(#sharing_modal[phx-hook="RailsStimulus"][phx-update="ignore"] form[data-sharing-modal-target="form"][action="/stats/2024/3/sharing"][method="post"] input[name="_method"][value="patch"])
             )

      assert has_element?(view, ~s(#sharing_modal input[name="authenticity_token"]))
      assert has_element?(view, ~s(#sharing_modal option[value="1h"][selected="selected"]))
      assert has_element?(view, ~s(#sharing_modal #sharing-link-display input[value=""]))
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

      {:ok, view, _html} = live_as(user, "/stats")

      assert has_element?(
               view,
               ~s([role="alert"][data-controller="removals"] a[href*="utm_medium=data_window"][href*="utm_content=stats_index"])
             )

      assert has_element?(view, "#chart-year-locked-2023[phx-update='ignore']")
      assert has_element?(view, "a.tooltip.tooltip-bottom[data-tip] span.badge")
      {:ok, month, _html} = live_as(user, "/stats/#{today.year}/#{today.month}")
      assert has_element?(month, ~s(#sharing_modal a.btn-primary[href*="utm_content=sharing"]))
      refute has_element?(month, ~s(#sharing_modal [data-controller="sharing-modal"]))
    end
  end
end
