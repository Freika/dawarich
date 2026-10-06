defmodule DawarichWeb.MapLiveTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.FormIsolation

  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})

    user =
      RailsUser.insert!(%{
        id: 6001,
        email: "a6-live@dawarich.test",
        api_key: "a6-live-key",
        settings: %{"timezone" => "Europe/Berlin", "onboarding_completed" => true}
      })

    %{user: user}
  end

  defp live_as(user, path),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  test "signed out, both paths redirect to sign-in" do
    for path <- ["/map", "/map/v2?panel=timeline"],
        do:
          assert(
            redirected_to(get(build_conn(), path), 302) == "http://www.example.com/users/sign_in"
          )
  end

  test "signed in, both paths render the map layout with Rails' title", %{user: user} do
    for path <- ["/map", "/map/v2"] do
      html = RailsUser.signed_in(user.id) |> get(path) |> html_response(200)
      assert_form_isolated(html)
      assert html =~ ">Map | Dawarich</title>"
      assert html =~ "width=device-width,initial-scale=1,viewport-fit=cover"
      assert html =~ ~s(<body class="h-screen !h-[100dvh] overflow-hidden relative">)
      assert html =~ ~s(id="map-footer")
      refute html =~ "locale-suggestion"
      refute html =~ "turbo-refresh-method"
    end
  end

  test "HEAD answers without a body", %{user: user} do
    conn = head(RailsUser.signed_in(user.id), "/map/v2")
    assert conn.status == 200
    assert conn.resp_body == ""
  end

  test "the Rails regions are LiveView-ignored MapShell hooks that Turbo may drive", %{user: user} do
    {:ok, view, _html} = live_as(user, "/map/v2")
    assert_form_isolated(render(view))

    for selector <- ["div#map-shell", "turbo-frame#share-link-modal"],
        do:
          assert(
            has_element?(
              view,
              "#{selector}[phx-hook='MapShell'][phx-update='ignore'][data-turbo='true']"
            ),
            selector
          )
  end

  test "the head carries Rails' translations and imports, and Phoenix's own entries win", %{
    user: user
  } do
    :persistent_term.put({DawarichWeb.Assets, :rails_imports}, %{
      "maplibre-gl" => "/maplibre/6.4.1/maplibre-gl.mjs",
      "app" => "/assets/should-not-win.js"
    })

    on_exit(fn -> :persistent_term.erase({DawarichWeb.Assets, :rails_imports}) end)
    html = RailsUser.signed_in(user.id) |> get("/map/v2") |> html_response(200)
    head = html |> LazyHTML.from_document() |> LazyHTML.query("head")

    imports =
      head
      |> LazyHTML.query("script[type='importmap']")
      |> LazyHTML.text()
      |> Jason.decode!()
      |> Map.fetch!("imports")

    assert imports["maplibre-gl"] == "/maplibre/6.4.1/maplibre-gl.mjs"
    assert imports["app"] =~ "/phoenix/js/app.js?vsn="

    translations =
      head |> LazyHTML.query("script#i18n-translations") |> LazyHTML.text() |> Jason.decode!()

    assert Map.has_key?(translations, "transportation_modes")
    refute html =~ ~s(import "chartkick")
  end

  test "the translations script matches Rails' byte layout, with no formatter-added whitespace",
       %{user: user} do
    html = RailsUser.signed_in(user.id) |> get("/map/v2") |> html_response(200)

    assert html =~
             ~r/<script id="i18n-translations" type="application\/json" data-turbo-track="reload">\{/
  end

  describe "the page" do
    setup do
      System.put_env("JWT_SECRET_KEY", "phoenix-a6-jwt-fixture-secret-not-for-production")
      on_exit(fn -> System.delete_env("JWT_SECRET_KEY") end)
    end

    test "the map page retains the ActionCable URL and realtime values", %{user: user} do
      for live_mode <- [true, false], path <- ["/map", "/map/v2"] do
        Repo.query!("UPDATE users SET settings = settings || $1::jsonb WHERE id = $2", [
          %{"live_map_enabled" => live_mode},
          user.id
        ])

        html = RailsUser.signed_in(user.id) |> get(path) |> html_response(200)
        doc = LazyHTML.from_document(html)

        assert LazyHTML.attribute(LazyHTML.query(doc, "meta[name='action-cable-url']"), "content") ==
                 ["/cable"]

        {:ok, view, _html} = live_as(user, path)
        root = "#maps-maplibre-container[data-controller~='maps--maplibre-realtime']"
        assert has_element?(view, "#{root}[data-maps--maplibre-realtime-enabled-value='true']")

        assert has_element?(
                 view,
                 "#{root}[data-maps--maplibre-realtime-live-mode-value='#{live_mode}']"
               )
      end
    end

    test "the map root carries Rails' values", %{user: user} do
      Repo.query!(
        "UPDATE users SET settings = settings || '{\"live_map_enabled\": false}' WHERE id = $1",
        [user.id]
      )

      {:ok, view, _html} = live_as(user, "/map/v2?panel=timeline&date=2026-05-28&import_id=12x")
      root = "#maps-maplibre-container"
      assert has_element?(view, "#{root}[data-maps--maplibre-api-key-value='a6-live-key']")

      assert has_element?(
               view,
               "#{root}[data-maps--maplibre-start-date-value='2026-05-28T00:00:00+02:00']"
             )

      assert has_element?(view, "#{root}[data-maps--maplibre-timezone-value='Europe/Berlin']")
      assert has_element?(view, "#{root}[data-maps--maplibre-import-id-value='']")
      assert has_element?(view, "#{root}[data-maps--maplibre-realtime-live-mode-value='false']")

      assert has_element?(
               view,
               "#{root} [data-maps--maplibre-target='container'].panel-open.panel-timeline-expanded"
             )

      refute has_element?(view, "#{root}[data-maps--maplibre-place-latitude-value]")
      assert has_element?(view, "turbo-frame#place-drawer:not([src])")
    end

    test "the date navigation keeps panel and import_id and Rails' link order", %{user: user} do
      {:ok, view, _html} = live_as(user, "/map/v2?panel=timeline&date=2026-05-28&import_id=12x")

      assert has_element?(
               view,
               "form[action='/map/v2?import_id=12x'][method='get'] input[type='hidden'][name='panel'][value='timeline']"
             )

      assert has_element?(view, "input[name='start_at'][value='2026-05-28T00:00']")

      prev =
        "/map/v2?end_at=2026-05-27T23%3A59%3A59%2B02%3A00&import_id=12x&panel=timeline&start_at=2026-05-27T00%3A00%3A00%2B02%3A00"

      assert has_element?(view, "a[href='#{prev}']")

      assert has_element?(
               view,
               "a[data-turbo-frame='share-link-modal'][href='/share_links/hub?end_date=2026-05-28&start_date=2026-05-28']"
             )

      {:ok, plain, _html} = live_as(user, "/map/v2")
      refute has_element?(plain, "input[name='panel']")
      refute has_element?(plain, "a[href*='import_id=']")
      refute has_element?(plain, "a[href*='panel=']")
    end

    test "a place of another user is Rails' 404", %{user: user} do
      other = RailsUser.insert!(%{id: 6002, email: "a6-live-other@dawarich.test"})

      Repo.query!(
        "INSERT INTO places (id, user_id, name, latitude, longitude, created_at, updated_at) VALUES (6090, $1, 'x', 1, 1, now(), now())",
        [other.id]
      )

      assert_error_sent 404, fn ->
        RailsUser.signed_in(user.id) |> get("/map/v2?place_id=6090")
      end
    end

    test "rails_flash shows only success and error flashes", %{user: user} do
      {:ok, view, _html} = live_as(user, "/map/v2")

      refute render_hook(view, "rails_flash", %{"type" => "info", "message" => "a6-unwanted"}) =~
               "a6-unwanted"

      assert render_hook(view, "rails_flash", %{
               "type" => "success",
               "message" => "Re-classification started"
             }) =~ "alert-success"
    end

    test "the panel: Turbo-permanent, timeline classes, Layers tab state, the Pro gates", %{
      user: user
    } do
      {:ok, view, _html} = live_as(user, "/map/v2?panel=timeline")

      assert has_element?(
               view,
               "#map-settings-panel[data-turbo-permanent].map-control-panel.open.timeline-expanded[data-controller='map-panel']"
             )

      refute has_element?(view, "[data-tab-content='layers'].active")

      assert has_element?(
               view,
               "[data-tab-content='search'] input[data-maps--maplibre-target='searchInput']"
             )

      refute has_element?(view, "[data-tab-content='links']")
      refute has_element?(view, "[data-maps--maplibre-target='flightsToggle']")
      assert has_element?(view, "[data-maps--maplibre-target='familyToggle']")

      {:ok, plain, _html} = live_as(user, "/map/v2")
      assert has_element?(plain, "[data-tab-content='layers'].active")
      refute has_element?(plain, "#map-settings-panel.open")
    end

    test "the Layers places filter lists every tag in name order", %{user: user} do
      stamp = NaiveDateTime.utc_now(:second)

      Repo.insert_all(
        "tags",
        for {id, name} <- [{6011, "Zoo"}, {6012, "Alpha"}] do
          %{
            id: id,
            name: name,
            color: "#123456",
            icon: nil,
            user_id: user.id,
            created_at: stamp,
            updated_at: stamp
          }
        end
      )

      {:ok, view, _html} = live_as(user, "/map/v2")
      html = render(view)

      [alpha, zoo] =
        for id <- ~w(6012 6011),
            do: :binary.match(html, ~s(name="place_tag_ids[]" value="#{id}")) |> elem(0)

      assert alpha < zoo

      assert has_element?(
               view,
               "input[name='place_tag_ids[]'][value='6012'] + span[style='border-color: #123456; color: #123456;']"
             )
    end

    test "the timeline rail: the calendar frame's month, Rails' frame ids, up to eight tag chips",
         %{user: user} do
      stamp = NaiveDateTime.utc_now(:second)

      Repo.insert_all(
        "tags",
        for i <- 1..9 do
          %{
            id: 6020 + i,
            name: "Chip #{i}",
            color: if(i == 1, do: nil, else: "#abcdef"),
            icon: if(i == 2, do: "🏠"),
            user_id: user.id,
            created_at: stamp,
            updated_at: stamp
          }
        end
      )

      {:ok, view, _html} = live_as(user, "/map/v2?panel=timeline&date=2026-05-28")

      tab =
        "[data-tab-content='timeline-feed'].active .timeline-tab-content[data-controller='timeline-feed']"

      assert has_element?(
               view,
               "#{tab} turbo-frame#timeline-calendar-frame[src='/map/timeline_feeds/calendar?month=2026-05'][loading='lazy']"
             )

      assert has_element?(
               view,
               "#{tab} turbo-frame#timeline-feed-frame[data-timeline-feed-target='visitListFrame'][data-maps--maplibre-target='timelineFeedContainer']"
             )

      assert has_element?(
               view,
               "#{tab} a[data-testid='tags-manage-link'][href='/tags'][target='_blank']"
             )

      assert render(view)
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(".timeline-rail__tags button.tag-chip")
             |> Enum.count() ==
               8

      assert has_element?(view, "button.tag-chip[data-tag-name='chip 1']:not([style])")

      assert has_element?(
               view,
               "button.tag-chip[data-tag-name='chip 3'][style='background-color: #abcdef;']"
             )
    end

    test "Settings: the theme swatches, the tile categories and POI groups the user hid, the modes",
         %{user: user} do
      Repo.query!(
        ~s(UPDATE users SET settings = settings || '{"maps": {"hidden_tile_categories": ["roads"], "disabled_poi_groups": ["cycling"]}, "enabled_transportation_modes": ["train"]}' WHERE id = $1),
        [user.id]
      )

      {:ok, view, _html} = live_as(user, "/map/v2")

      assert has_element?(
               view,
               "[data-map-theme-editor-target='swatch'][data-key='blueprint'][data-name='Blueprint']"
             )

      assert has_element?(
               view,
               "input[data-tile-category='roads'][data-custom-supported='true']:not([checked])"
             )

      assert has_element?(
               view,
               "input[data-tile-category='road_labels'][data-custom-supported='false'][checked]"
             )

      assert has_element?(view, "input[data-poi-group='cycling']:not([checked])")
      assert has_element?(view, "input[data-testid='enabled-mode-train'][checked]")
      assert has_element?(view, "input[data-testid='enabled-mode-walking']:not([checked])")

      refute has_element?(view, "form.button_to[action='/tracks/recalculation']")

      assert has_element?(
               view,
               "button[data-testid='reclassify-history-button']:not([disabled]) + input[type='hidden'][name='authenticity_token']"
             )
    end

    test "Tools: the Immich panel only for a configured Pro user", %{user: user} do
      {:ok, view, _html} = live_as(user, "/map/v2")
      refute has_element?(view, "#immich-enrich-toggle-btn")

      Repo.query!(
        ~s(UPDATE users SET settings = settings || '{"immich_url": "https://immich.a6.test", "immich_api_key": "k"}' WHERE id = $1),
        [user.id]
      )

      {:ok, view, _html} = live_as(user, "/map/v2")
      assert has_element?(view, "#immich-enrich-toggle-btn")

      assert has_element?(
               view,
               "[data-controller='maps--immich-enrich'][data-maps--immich-enrich-api-key-value='a6-live-key'][data-maps--immich-enrich-immich-url-value='https://immich.a6.test']"
             )
    end

    test "the studios: Rails' request-spec markers, fonts in Rails' order, the URLs", %{
      user: user
    } do
      System.put_env("PRINT_ORDER_URL", "https://prints.dawarich.app/api/orders")
      on_exit(fn -> System.delete_env("PRINT_ORDER_URL") end)
      {:ok, view, html} = live_as(user, "/map/v2")
      assert html =~ "map-button-poster"
      assert has_element?(view, "[data-poster-studio-editor-target='dateStart']")
      assert has_element?(view, "[data-video-studio-target='dateStart']")
      assert has_element?(view, "[data-video-studio-target='dateEnd']")
      assert html =~ "video-studio#applyDateTimeRange"
      assert has_element?(view, "[data-poster-studio-editor-target='trackOpacity'][value='100']")

      assert has_element?(
               view,
               "#poster-studio[data-poster-studio-editor-print-order-url-value='https://prints.dawarich.app/api/orders']"
             )

      assert has_element?(
               view,
               "#video-studio[data-video-studio-upload-url-value='http://www.example.com/rails/active_storage/direct_uploads'][data-video-studio-create-url-value='/route_videos']"
             )

      [fonts] =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#poster-studio")
        |> LazyHTML.attribute("data-poster-studio-editor-fonts-value")

      keys = Jason.decode!(fonts, objects: :ordered_objects).values |> Enum.map(&elem(&1, 0))

      assert keys ==
               ~w(inter-400 inter-700 oswald-400 oswald-700 playfair-display-400 playfair-display-700 jetbrains-mono-400 jetbrains-mono-700)

      assert Jason.decode!(fonts)["oswald-700"] =~
               ~r{\A/assets/poster/oswald-700(-[0-9a-f]+)?\.woff2\z}
    end

    test "PRINT_ORDER_URL overrides the order endpoint", %{user: user} do
      System.put_env("PRINT_ORDER_URL", "http://localhost:3001/api/orders")
      on_exit(fn -> System.delete_env("PRINT_ORDER_URL") end)
      {:ok, view, _html} = live_as(user, "/map/v2")

      assert has_element?(
               view,
               "#poster-studio[data-poster-studio-editor-print-order-url-value='http://localhost:3001/api/orders']"
             )
    end

    test "the poster gallery links Rails' blob paths and streams on the user's signed name", %{
      user: user
    } do
      stamp = NaiveDateTime.utc_now(:second)

      Repo.insert_all("posters", [
        %{
          id: 6031,
          name: "A6 live poster",
          status: 2,
          settings: %{},
          user_id: user.id,
          created_at: stamp,
          updated_at: stamp
        }
      ])

      Repo.insert_all("active_storage_blobs", [
        %{
          id: 6032,
          key: "a6live6032",
          filename: "a6.png",
          byte_size: 1,
          service_name: "test",
          created_at: stamp
        }
      ])

      Repo.insert_all("active_storage_attachments", [
        %{name: "image", record_type: "Poster", record_id: 6031, blob_id: 6032, created_at: stamp}
      ])

      {:ok, view, _html} = live_as(user, "/map/v2")
      src = Dawarich.MapGallery.blob_path(%{id: 6032, filename: "a6.png"})
      assert has_element?(view, "#poster-gallery-list #poster_6031 img[src='#{src}']")
      assert has_element?(view, "#poster_6031 a[href='#{src}?disposition=attachment']")

      assert has_element?(
               view,
               "#poster_6031 a[data-turbo-method='delete'][href='/posters/6031']"
             )

      assert has_element?(
               view,
               "turbo-cable-stream-source[channel='Turbo::StreamsChannel'][signed-stream-name='#{Dawarich.RailsMessages.stream_name([{:user, user.id}, "posters"])}']"
             )
    end
  end

  describe "controls the LiveView doesn't own survive its join (A5 s3 lesson)" do
    @map_control ":is(input:not([type=button]):not([type=reset]), select, textarea, button[name]):not(form[phx-submit] *):not(form[phx-change] *)"
    @unpatched ":not([phx-update=ignore]):not([phx-update=ignore] *)"

    test "every control outside phx-change/phx-submit handling sits under an ignored, id-bearing ancestor",
         %{user: user} do
      {:ok, view, _html} = live_as(user, "/map/v2")
      doc = view |> render() |> LazyHTML.from_fragment()

      all = doc |> LazyHTML.query(@map_control)
      assert Enum.count(all) > 50

      unprotected = doc |> LazyHTML.query(@map_control <> @unpatched)
      assert Enum.count(unprotected) == 0, inspect(LazyHTML.attribute(unprotected, "id"))
    end

    test "the ignored ancestors each carry their own stable, unique id", %{user: user} do
      {:ok, view, _html} = live_as(user, "/map/v2")
      doc = view |> render() |> LazyHTML.from_fragment()

      ids = doc |> LazyHTML.query("[phx-update=ignore]") |> LazyHTML.attribute("id")
      assert ids != []
      assert Enum.all?(ids, &(&1 != ""))
      assert Enum.uniq(ids) == ids
    end
  end
end
