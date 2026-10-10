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

    test "a rails_js page loads Rails' imports, translations and Chartkick; Phoenix's own entries win",
         %{user: user} do
      html = RailsUser.signed_in(user.id) |> get("/stats/2024/03") |> html_response(200)
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

    test "a signed-in page without rails_js loads Rails' imports and translations, not Chartkick",
         %{user: user} do
      html = RailsUser.signed_in(user.id) |> get("/notifications") |> html_response(200)
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

      assert translations["demo"]["already_loaded"] == "Demo data already loaded"
      refute html =~ ~r/import "chartkick"/
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

      assert root.(%{}) =~ ~r/import "chartkick"/
      html = root.(%{rails_charts: false})
      assert html =~ ~s(id="i18n-translations")
      refute html =~ ~r/import "chartkick"/
    end

    test "rails_flash shows only success and error flashes", %{user: user} do
      {:ok, view, _html} = live_as(user, "/stats/2024/03")

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
          RailsUser.signed_in(user.id) |> get("/stats?locale=#{locale}") |> html_response(200)

        assert Enum.map(texts(html, "#stats-total"), &String.trim/1) == [
                 "#{total} #{unit}"
               ]

        assert texts(html, "article > a:first-child") == ["2024", "2023"]
        cards = if unit == "km", do: ["50 km", "20 km"], else: ["31 mi", "12 mi"]

        assert Enum.map(texts(html, "p[id^=stats-year-total-]"), &String.trim/1) ==
                 cards

        assert html =~ if(locale == "de", do: "Statistiken", else: "Statistics")
      end
    end

    test "native index retains source totals ready counts and one card per year", %{user: user} do
      {:ok, view, html} = live_as(user, "/stats")
      assert html =~ ">Statistics | Dawarich</title>"
      assert has_element?(view, "#stats-total", "70 km")
      assert :sys.get_state(view.pid).socket.assigns.data.points.total == 77
      assert :sys.get_state(view.pid).socket.assigns.data.points.percentage == 100
      assert has_element?(view, "#stats-without-data", "1 points without data")
      assert has_element?(view, "#stats-update", "Update stats")
      assert texts(html, "article > a:first-child") == ["2024", "2023"]
      assert has_element?(view, "#stats-year-2024-places", "2 countries, 2 cities")
      assert has_element?(view, "#stats-year-2023-places", "1 countries, 1 cities")
      refute html =~ "data-turbo-method"
    end

    test "native place dialogs switch source countries and cities without losing totals", %{
      user: user
    } do
      {:ok, view, _} = live_as(user, "/stats")
      view |> element("button[phx-value-kind=countries]") |> render_click()
      assert texts(render(view), "#stats-dialog li") == ["Czechia", "Germany"]
      render_click(view, "close_dialog", %{})
      view |> element("button[phx-value-kind=cities]") |> render_click()
      assert texts(render(view), "#stats-dialog li") == ["Berlin", "Prague"]
      render_click(view, "close_dialog", %{})
      assert has_element?(view, "#stats-total", "70 km")
      refute has_element?(view, "#stats-dialog")
    end

    test "native charts update only their plot island and retain source accessible values", %{
      user: user
    } do
      {:ok, view, html} = live_as(user, "/stats")
      assert has_element?(view, "#stats-year-2024[phx-hook=NativeChart]")
      assert has_element?(view, "#stats-year-2024-plot[phx-update=ignore]")
      assert has_element?(view, "#stats-year-2024 details table td", "March")

      [payload] =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("#stats-year-2024")
        |> LazyHTML.attribute("data-chart")

      assert Enum.slice(Jason.decode!(payload)["data"], 2, 2) == [["March", 38], ["April", 12]]
      refute html =~ "RailsStimulus"
      refute has_element?(view, "#stats-year-2024[phx-update=ignore]")
    end

    test "native year chart cards and links retain source window values", %{user: user} do
      {:ok, view, html} = live_as(user, "/stats/2024")
      assert html =~ ">Statistics for 2024 year | Dawarich</title>"
      assert has_element?(view, "a[href='/stats/2024/3']", "March")
      assert has_element?(view, "#stats-month-places-3", "Berlin")
      assert has_element?(view, "#stats-month-places-3", "Prague")
      assert :sys.get_state(view.pid).socket.assigns.data.distances |> Enum.sum() == 50400
      assert has_element?(view, "#stats-native-chart[phx-hook=NativeChart]")
    end

    test "a month without a stat is Rails' empty state with HTTP 200", %{user: user} do
      html = RailsUser.signed_in(user.id) |> get("/stats/2024/2") |> html_response(200)
      assert html =~ ">February 2024 Monthly Digest | Dawarich</title>"
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

      assert has_element?(view, "#stats-window-alert[role=alert]")
      assert has_element?(view, "#stats-locked-2023")
      assert has_element?(view, "button[phx-click=upgrade]")
      {:ok, month, _html} = live_as(user, "/stats/#{today.year}/#{today.month}")
      assert has_element?(month, ~s(#sharing_modal a.btn-primary[href*="utm_content=sharing"]))
      refute has_element?(month, ~s(#sharing_modal [data-controller="sharing-modal"]))
    end
  end
end
