defmodule DawarichWeb.MapLiveTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

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

  defp config(view, selector, attribute) do
    [value] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute(attribute)

    Jason.decode!(value)
  end

  defp map_config(view), do: config(view, "#native-map", "data-map-config")

  defp settings(user, values),
    do:
      Repo.query!("UPDATE users SET settings = settings || $1::jsonb WHERE id = $2", [
        values,
        user.id
      ])

  defp tags(user, entries) do
    stamp = NaiveDateTime.utc_now(:second)

    Repo.insert_all(
      "tags",
      for(
        {id, name, color, icon} <- entries,
        do: %{
          id: id,
          name: name,
          color: color,
          icon: icon,
          user_id: user.id,
          created_at: stamp,
          updated_at: stamp
        }
      )
    )
  end

  test "signed out, both paths redirect to sign-in" do
    for path <- ["/map", "/map/v2?panel=timeline"],
        do:
          assert(
            redirected_to(get(build_conn(), path), 302) == "http://www.example.com/users/sign_in"
          )
  end

  test "signed in aliases render the native map document with the map title", %{user: user} do
    for path <- ["/map", "/map/v2"] do
      html = RailsUser.signed_in(user.id) |> get(path) |> html_response(200)
      assert html =~ ">Map | Dawarich</title>"
      assert html =~ "width=device-width,initial-scale=1"
      assert html =~ "native-map-page"

      for marker <- ~w(locale-suggestion turbo-refresh-method MapShell data-controller),
          do: refute(html =~ marker)
    end
  end

  test "HEAD answers without a body", %{user: user} do
    conn = head(RailsUser.signed_in(user.id), "/map/v2")
    assert conn.status == 200
    assert conn.resp_body == ""
  end

  test "native map and studios survive a server panel patch with keyed owners", %{user: user} do
    {:ok, view, _} = live_as(user, "/map/v2")

    for {id, hook} <- [
          {"native-map", "Map"},
          {"native-poster-studio", "PosterStudio"},
          {"native-video-studio", "VideoStudio"}
        ] do
      assert has_element?(view, "##{id}[phx-hook='#{hook}']")
    end

    view |> element("[data-testid=map-button-settings]") |> render_click()
    assert has_element?(view, "#native-map-settings")
    assert has_element?(view, "#native-map[phx-update=ignore]")
    refute render(view) =~ "MapShell"
  end

  test "native head loads its entry despite cached legacy imports", %{user: user} do
    :persistent_term.put({DawarichWeb.Assets, :rails_imports}, %{
      "app" => "/assets/should-not-win.js",
      "maplibre-gl" => "/legacy/maplibre.mjs"
    })

    on_exit(fn -> :persistent_term.erase({DawarichWeb.Assets, :rails_imports}) end)
    html = RailsUser.signed_in(user.id) |> get("/map/v2") |> html_response(200)
    assert html =~ "/native/app"

    for marker <- ~w(importmap should-not-win legacy/maplibre chartkick),
        do: refute(html =~ marker)
  end

  test "native localized config decodes reserved placeholders without a global script", %{
    user: user
  } do
    {:ok, view, _} = live_as(user, "/map/v2")
    video = config(view, "#native-video-studio", "data-video-config")
    assert Enum.any?(Map.values(video["strings"]), &String.contains?(&1, "%{format}"))
    refute has_element?(view, "script#i18n-translations")
    assert map_size(map_config(view)["uiLabels"]) > 0
  end

  test "native subscription admission preserves live mode settings without cable secrets", %{
    user: user
  } do
    for enabled <- [true, false] do
      settings(user, %{"live_map_enabled" => enabled})
      {:ok, view, html} = live_as(user, "/map/v2")
      state = :sys.get_state(view.pid).socket.assigns
      assert state.page.live_map == enabled
      assert state.native_subscriptions.descriptor.scope.user.id == user.id

      for marker <- ~w(action-cable-url a6-live-key turbo-cable-stream-source),
          do: refute(html =~ marker)
    end
  end

  test "native map config carries typed range timezone and no credential projection", %{
    user: user
  } do
    settings(user, %{"live_map_enabled" => false})
    {:ok, view, html} = live_as(user, "/map/v2?panel=timeline&date=2026-05-28&import_id=12x")
    data = map_config(view)
    assert data["range"]["startAt"] == "2026-05-28T00:00:00+02:00"
    assert data["range"]["timezone"] == "Europe/Berlin"
    assert data["panel"] == "timeline"
    assert :sys.get_state(view.pid).socket.assigns.page.import_id == nil
    refute html =~ "a6-live-key"
    refute Map.has_key?(data, "apiKey")
    assert has_element?(view, "#native-map-panel")
    refute has_element?(view, "turbo-frame#place-drawer")
  end

  test "native day navigation retains panel import and profile offset", %{user: user} do
    {:ok, view, _} = live_as(user, "/map/v2?panel=timeline&date=2026-05-28&import_id=12")
    assert has_element?(view, "#native-map-dates input[name=start_at][value='2026-05-28T00:00']")
    view |> element("#native-map-prev-day") |> render_click()
    patch = assert_patch(view)
    query = URI.decode_query(URI.parse(patch).query)
    assert query["panel"] == "timeline"
    assert query["import_id"] == "12"
    assert String.starts_with?(map_config(view)["range"]["startAt"], "2026-05-27")
    {:ok, plain, _} = live_as(user, "/map/v2")
    refute Map.has_key?(:sys.get_state(plain.pid).socket.assigns.map_url, "panel")
    refute Map.has_key?(:sys.get_state(plain.pid).socket.assigns.map_url, "import_id")
  end

  test "foreign place produces a typed native refusal without exposing its data", %{user: user} do
    other = RailsUser.insert!(%{id: 6002, email: "a6-live-other@dawarich.test"})

    Repo.query!(
      "INSERT INTO places (id, user_id, name, latitude, longitude, created_at, updated_at) VALUES (6090, $1, 'foreign-place-hidden', 1, 1, now(), now())",
      [other.id]
    )

    {:ok, view, html} = live_as(user, "/map/v2?place_id=6090")
    assert has_element?(view, "[role=alert]", "not_found")
    refute has_element?(view, "#native-map")
    refute html =~ "foreign-place-hidden"
  end

  test "unowned Rails flash events cannot inject native notices", %{user: user} do
    {:ok, view, _} = live_as(user, "/map/v2")

    for type <- ~w(info success error) do
      refute render_hook(view, "rails_flash", %{"type" => type, "message" => "unowned-flash"}) =~
               "unowned-flash"

      refute "unowned-flash" in Map.values(:sys.get_state(view.pid).socket.assigns.flash)
    end
  end

  test "native panel state changes through its launcher and close commands", %{user: user} do
    {:ok, view, _} = live_as(user, "/map/v2?panel=timeline")
    assert has_element?(view, "#native-map-panel")
    view |> element("[data-testid=map-button-layers]") |> render_click()
    assert map_config(view)["panel"] == "layers"
    assert has_element?(view, "#native-map-layers")
    refute has_element?(view, "#native-map-panel")
    view |> element("#native-map-panel-close") |> render_click()
    assert map_config(view)["panel"] == ""
    refute has_element?(view, "#native-map-layers")
  end

  test "native places filter preserves every owned tag name order and color", %{user: user} do
    settings(user, %{"enabled_map_layers" => ["Places"]})
    tags(user, [{6011, "Zoo", "#123456", nil}, {6012, "Alpha", "#123456", nil}])
    {:ok, view, _} = live_as(user, "/map/v2?panel=layers")

    names =
      render(view)
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-place-tag-name]")
      |> LazyHTML.attribute("data-place-tag-name")

    assert names == ["Alpha", "Zoo"]

    assert has_element?(
             view,
             "input[name='place_tag_ids[]'][value='6012'] + span[style='border-color: #123456; color: #123456;']"
           )
  end

  test "native calendar loads its month and bounds timeline tag chips to eight", %{user: user} do
    tags(
      user,
      for(
        i <- 1..9,
        do:
          {6020 + i, "Chip #{i}", if(i == 1, do: nil, else: "#abcdef"),
           if(i == 2, do: "🏠", else: nil)}
      )
    )

    {:ok, view, _} = live_as(user, "/map/v2?panel=timeline&date=2026-05-28")
    render_async(view)
    assert :sys.get_state(view.pid).socket.assigns.calendar.summary.month == "2026-05"

    chips =
      render(view) |> LazyHTML.from_fragment() |> LazyHTML.query("#native-timeline-tags button")

    assert Enum.count(chips) == 8

    styles =
      render(view)
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("button[data-tag-name='chip 1']")
      |> LazyHTML.attribute("style")

    assert Enum.all?(styles, &(&1 == ""))
    assert has_element?(view, "button[data-tag-name='chip 2']", "🏠")

    assert has_element?(
             view,
             "button[data-tag-name='chip 3'][style='background-color: #abcdef;']"
           )

    view |> element("button[data-tag-name='chip 3']") |> render_click()
    assert has_element?(view, "button[data-tag-name='chip 3'][aria-pressed=true]")
    refute has_element?(view, "turbo-frame")
  end

  test "native settings retain hidden tile POI and transport choices", %{user: user} do
    settings(user, %{
      "maps" => %{"hidden_tile_categories" => ["roads"], "disabled_poi_groups" => ["cycling"]},
      "enabled_transportation_modes" => ["train"]
    })

    {:ok, view, _} = live_as(user, "/map/v2?panel=settings")
    assert has_element?(view, "#native-theme-presets [data-theme-key=blueprint]")
    refute has_element?(view, "#native-layers-form input[name='tiles[]'][value=roads][checked]")

    assert has_element?(
             view,
             "#native-layers-form input[name='tiles[]'][value=road_labels][checked]"
           )

    refute has_element?(view, "#native-layers-form input[name='poi[]'][value=cycling][checked]")

    assert has_element?(
             view,
             "#native-transport-form input[name='modes[]'][value=train][checked]"
           )

    refute has_element?(
             view,
             "#native-transport-form input[name='modes[]'][value=walking][checked]"
           )

    assert has_element?(view, "#native-transport-apply[disabled]")
    view |> form("#native-transport-form", %{"modes" => ["walking"]}) |> render_change()
    refute has_element?(view, "#native-transport-apply[disabled]")
    assert Dawarich.Accounts.get(user.id).settings["enabled_transportation_modes"] == ["train"]
  end

  test "native Immich tools require configured Pro admission and hide provider credentials", %{
    user: user
  } do
    {:ok, view, _} = live_as(user, "/map/v2?panel=tools")
    refute has_element?(view, "#native-enrichment-scan")

    settings(user, %{
      "immich_url" => "https://immich.a6.test",
      "immich_api_key" => "synthetic-immich-key"
    })

    {:ok, view, html} = live_as(user, "/map/v2?panel=tools")
    assert has_element?(view, "#native-enrichment-scan")
    for marker <- ~w(immich.a6.test synthetic-immich-key a6-live-key), do: refute(html =~ marker)
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [user.id])
    {:ok, lite, _} = live_as(user, "/map/v2?panel=tools")
    refute has_element?(lite, "#native-enrichment-scan")
  end

  test "native studios preserve font order date controls and native save commands", %{user: user} do
    {:ok, view, html} = live_as(user, "/map/v2")

    for selector <- [
          "[data-testid=map-button-poster]",
          "[data-poster-date-start]",
          "[data-video-start]",
          "[data-video-end]"
        ],
        do: assert(has_element?(view, selector))

    [raw] =
      render(view)
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#native-poster-studio")
      |> LazyHTML.attribute("data-poster-config")

    ordered =
      Jason.decode!(raw, objects: :ordered_objects).values
      |> Enum.find_value(fn {k, v} -> if k == "fonts", do: v.values end)

    assert Enum.map(ordered, &elem(&1, 0)) ==
             ~w(inter-400 inter-700 oswald-400 oswald-700 playfair-display-400 playfair-display-700 jetbrains-mono-400 jetbrains-mono-700)

    assert config(view, "#native-poster-studio", "data-poster-config")["fonts"]["oswald-700"] =~
             ~r{\A/native/poster/oswald-700(-[0-9a-f]+)?\.woff2\z}

    refute html =~ "/rails/active_storage/direct_uploads"

    assert render_hook(element(view, "#native-video-studio"), "video:upload_target", %{
             "byte_size" => 0
           }) =~
             "native-video-studio"
  end

  test "PRINT_ORDER_URL overrides the native order endpoint", %{user: user} do
    System.put_env("PRINT_ORDER_URL", "http://localhost:3001/api/orders")
    on_exit(fn -> System.delete_env("PRINT_ORDER_URL") end)
    {:ok, view, _} = live_as(user, "/map/v2")

    assert config(view, "#native-poster-studio", "data-poster-config")["printOrderUrl"] ==
             "http://localhost:3001/api/orders"
  end

  test "native poster gallery retains download URLs and deletes through its scoped owner", %{
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

    {:ok, view, _} = live_as(user, "/map/v2")
    src = Dawarich.MapGallery.blob_path(%{id: 6032, filename: "a6.png"})
    assert has_element?(view, "#native-poster-gallery-list #poster_6031 img[src='#{src}']")
    assert has_element?(view, "#poster_6031 a[href='#{src}?disposition=attachment']")
    view |> element("#poster_6031 button[phx-click='poster:delete']") |> render_click()
    refute has_element?(view, "#poster_6031")
    assert Repo.query!("SELECT id FROM posters WHERE id=6031").rows == []
    refute has_element?(view, "turbo-cable-stream-source")
  end

  test "native browser controls outside server forms have ignored keyed owners", %{user: user} do
    {:ok, view, _} = live_as(user, "/map/v2?panel=settings")
    doc = render(view) |> LazyHTML.from_fragment()

    selector =
      ":is(input:not([type=button]):not([type=reset]):not([type=hidden]),select,textarea,button[name]):not(form[phx-submit] *):not(form[phx-change] *)"

    assert Enum.count(LazyHTML.query(doc, selector)) > 0

    unprotected =
      LazyHTML.query(doc, selector <> ":not([phx-update=ignore]):not([phx-update=ignore] *)")

    assert Enum.count(unprotected) == 0, inspect(LazyHTML.attribute(unprotected, "name"))
  end

  test "the ignored ancestors each carry their own stable, unique id", %{user: user} do
    {:ok, view, _} = live_as(user, "/map/v2")

    ids =
      render(view)
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[phx-update=ignore]")
      |> LazyHTML.attribute("id")

    assert ids != []
    assert Enum.all?(ids, &(&1 != ""))
    assert Enum.uniq(ids) == ids
  end
end
