defmodule DawarichWeb.NativeMapSettingsSectionsTest do
  use Dawarich.DataCase, async: false
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Maps}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.MapLive.SettingsCommands
  @endpoint DawarichWeb.Endpoint

  defmodule Host do
    use Phoenix.LiveView

    def mount(_params, session, socket) do
      scope = Maps.principal(Accounts.get(session["user_id"]), "en")
      {:ok, socket |> assign(current_scope: scope) |> SettingsCommands.load()}
    end

    def handle_event(event, params, socket),
      do: SettingsCommands.handle_event(event, params, socket)

    def render(assigns) do
      ~H"""
      <DawarichWeb.NativeMapSettingsTab.tab
        settings={@map_settings}
        locale="en"
        panel="settings"
        page={%{full_access: true, badge_url: ""}}
      />
      <form id="native-reclassify" phx-submit="settings:reclassify"></form>
      """
    end
  end

  setup do
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "map-sections-#{id}@dawarich.test",
      plan: 1,
      status: 1,
      settings: %{"timezone" => "UTC"}
    })

    Repo.query!("UPDATE users SET settings = settings || $2 WHERE id=$1", [
      id,
      %{
        "immich_url" => "https://immich.example.test",
        "immich_api_key" => "synthetic-sections-secret",
        "maps" => %{"distance_unit" => "mi", "legacy" => "kept"}
      }
    ])

    on_exit(fn ->
      Dawarich.Redis.cache_command([
        "DEL",
        "recalculation_pending:#{id}",
        "anomaly_backfill_pending:#{id}"
      ])
    end)

    {:ok, view, _} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host, session: %{"user_id" => id})

    %{id: id, view: view}
  end

  test "default advanced values stay within browser constraints and submit", c do
    doc = c.view |> render() |> LazyHTML.from_fragment()

    for {"input", attrs, _} <-
          doc
          |> LazyHTML.query(
            "#native-map-settings-form input[type=number], #native-map-settings-form input[type=range]"
          )
          |> LazyHTML.to_tree() do
      attrs = Map.new(attrs)
      value = String.to_integer(attrs["value"])
      assert value >= String.to_integer(attrs["min"])
      if attrs["max"], do: assert(value <= String.to_integer(attrs["max"]))
    end

    assert has_element?(c.view, "input[name=fogOfWarThreshold][value='10']")

    c.view
    |> form("#native-map-settings-form", %{
      "metersBetweenRoutes" => "750",
      "minutesBetweenRoutes" => "45"
    })
    |> render_submit()

    assert stored(c.id)["meters_between_routes"] == "750"
    assert stored(c.id)["minutes_between_routes"] == "45"
  end

  test "an edited tracked field marks its section unsaved until Apply", c do
    c.view
    |> element("#native-map-settings-form")
    |> render_change(%{"_target" => ["metersBetweenRoutes"], "metersBetweenRoutes" => "900"})

    assert has_element?(c.view, "[data-dirty-badge]:not(.hidden)", "1 unsaved")
    assert stored(c.id)["meters_between_routes"] != "900"

    c.view
    |> form("#native-map-settings-form", %{"metersBetweenRoutes" => "900"})
    |> render_submit()

    assert stored(c.id)["meters_between_routes"] == "900"
    refute has_element?(c.view, "[data-dirty-badge]:not(.hidden)")
  end

  test "theme preset saves custom style with derived tokens and refuses unknown keys", c do
    c.view |> element("button[data-key=autumn]") |> render_click()

    assert stored(c.id)["maps_maplibre_style"] == "custom"

    assert %{"base" => "autumn", "tokens" => %{"bg" => "#FBF7F0"}} =
             stored(c.id)["maps_maplibre_custom_theme"]

    assert_push_event(c.view, "map:settings", %{settings: %{"maps_maplibre_style" => "custom"}})
    assert has_element?(c.view, "input[data-token=bg][value='#FBF7F0']")

    before = stored(c.id)
    render_hook(c.view, "settings:theme_preset", %{"key" => "../../package"})
    assert stored(c.id) == before
    assert has_element?(c.view, "[role=alert]")

    c.view
    |> element("#native-map-settings-form")
    |> render_change(%{"_target" => ["tokens", "bg"], "tokens" => %{"bg" => "#123456"}})

    theme = stored(c.id)["maps_maplibre_custom_theme"]
    assert theme["base"] == "autumn"
    assert theme["tokens"]["bg"] == "#123456"
  end

  test "base layer and POI toggles save hidden lists inside maps", c do
    c.view |> element("input[data-tile-category=roads]") |> render_click()
    c.view |> element("input[data-poi-group=cycling]") |> render_click()

    maps = stored(c.id)["maps"]
    assert maps["hidden_tile_categories"] == ["roads"]
    assert maps["disabled_poi_groups"] == ["cycling"]
    assert maps["distance_unit"] == "mi"
    assert maps["legacy"] == "kept"
    refute has_element?(c.view, "input[data-tile-category=roads][checked]")
    assert has_element?(c.view, "input[data-tile-category=rail][checked]")

    c.view |> element("input[data-tile-category=roads]") |> render_click()
    assert stored(c.id)["maps"]["hidden_tile_categories"] == []

    for {target, value} <- [
          {"globeProjection", "on"},
          {"trackColor", "#00FF00"},
          {"distanceUnit", "km"}
        ] do
      c.view
      |> element("#native-map-settings-form")
      |> render_change(%{"_target" => [target], target => value})
    end

    assert stored(c.id)["globe_projection"] == true
    assert stored(c.id)["track_color"] == "#00FF00"
    assert stored(c.id)["maps"]["distance_unit"] == "km"

    c.view |> element("[phx-click='settings:track_color_reset']") |> render_click()
    assert stored(c.id)["track_color"] == "#6366F1"
  end

  test "advanced fields save and reset restores defaults without dropping provider credentials",
       c do
    c.view
    |> form("#native-map-settings-form", %{
      "metersBetweenRoutes" => "900",
      "fogOfWarRadius" => "250"
    })
    |> render_submit(%{"gpsFilteringEnabled" => nil})

    assert %{
             "meters_between_routes" => "900",
             "fog_of_war_meters" => "250"
           } = stored(c.id)

    c.view |> element("[phx-click='settings:reset']") |> render_click()
    after_reset = stored(c.id)
    assert after_reset["meters_between_routes"] == "500"
    assert after_reset["fog_of_war_meters"] == "50"
    assert after_reset["gps_filtering_enabled"] == true
    assert after_reset["maps"]["hidden_tile_categories"] == []
    assert after_reset["immich_api_key"] == "synthetic-sections-secret"

    assert_push_event(c.view, "map:settings", %{settings: pushed})
    refute inspect(pushed) =~ "synthetic-sections-secret"
    refute render(c.view) =~ "synthetic-sections-secret"
    refute inspect(:sys.get_state(c.view.pid), limit: :infinity) =~ "synthetic-sections-secret"
  end

  test "recalculation and anomaly re-evaluation queue once with typed notices", c do
    Ownership.put!(Repo, "command:users.recalculate_data", :oban)
    Ownership.put!(Repo, "command:points.anomaly_backfill", :oban)

    c.view |> element("[phx-click='settings:recalculate']") |> render_click()
    assert has_element?(c.view, "#native-settings-notice", "Recalculation queued")
    c.view |> element("[phx-click='settings:recalculate']") |> render_click()
    assert has_element?(c.view, "[role=alert]")
    assert outbox(c.id, "users.recalculate_data") == 1

    c.view |> element("[phx-click='settings:reapply_anomalies']") |> render_click()
    assert has_element?(c.view, "#native-settings-notice", "Re-evaluation queued")
    assert outbox(c.id, "points.anomaly_backfill") == 1
  end

  defp stored(id), do: rows("SELECT settings FROM users WHERE id=$1", [id]) |> hd() |> hd()

  defp outbox(id, kind),
    do:
      rows(
        "SELECT count(*) FROM public.job_outbox WHERE command_type=$1 AND aggregate_id=$2",
        [kind, id]
      )
      |> hd()
      |> hd()
end
