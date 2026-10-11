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
      <DawarichWeb.NativeMapSettings.panel settings={@map_settings} locale="en" />
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

  test "theme preset saves custom style with derived tokens and refuses unknown keys", c do
    refute has_element?(c.view, "#native-theme-form")
    c.view |> element("#native-theme-presets [data-theme-key=autumn]") |> render_click()

    assert stored(c.id)["maps_maplibre_style"] == "custom"

    assert %{"base" => "autumn", "tokens" => %{"bg" => "#FBF7F0"}} =
             stored(c.id)["maps_maplibre_custom_theme"]

    assert_push_event(c.view, "map:settings", %{settings: %{"maps_maplibre_style" => "custom"}})
    assert has_element?(c.view, "#native-theme-form input[name='tokens[bg]'][value='#FBF7F0']")

    before = stored(c.id)
    render_hook(c.view, "settings:theme_preset", %{"key" => "../../package"})
    assert stored(c.id) == before
    assert has_element?(c.view, "#native-map-settings [role=alert]")

    c.view |> form("#native-theme-form", %{"tokens" => %{"bg" => "#123456"}}) |> render_submit()
    theme = stored(c.id)["maps_maplibre_custom_theme"]
    assert theme["base"] == "autumn"
    assert theme["tokens"]["bg"] == "#123456"
  end

  test "base layer and POI toggles save hidden lists inside maps", c do
    c.view
    |> form("#native-layers-form", %{"tiles" => ["roads", "water"], "poi" => ["cycling"]})
    |> render_submit()

    maps = stored(c.id)["maps"]

    assert maps["hidden_tile_categories"] ==
             Dawarich.Settings.MapForm.tile_categories() -- ["roads", "water"]

    assert maps["disabled_poi_groups"] == Dawarich.Settings.MapForm.poi_groups() -- ["cycling"]
    assert maps["distance_unit"] == "mi"
    assert maps["legacy"] == "kept"
    assert has_element?(c.view, "#native-layers-form input[name='tiles[]'][value=roads][checked]")
    refute has_element?(c.view, "#native-layers-form input[name='tiles[]'][value=rail][checked]")

    c.view
    |> form("#native-display-form", %{
      "globe_projection" => "true",
      "track_color" => "#00FF00",
      "distance_unit" => "km"
    })
    |> render_submit()

    assert stored(c.id)["globe_projection"] == true
    assert stored(c.id)["track_color"] == "#00FF00"
    assert stored(c.id)["maps"]["distance_unit"] == "km"

    c.view |> element("#native-track-color-reset") |> render_click()
    assert stored(c.id)["track_color"] == "#6366F1"
  end

  test "advanced fields save and reset restores defaults without dropping provider credentials",
       c do
    c.view
    |> form("#native-advanced-form", %{
      "meters_between_routes" => "900",
      "fog_of_war_meters" => "250",
      "gps_filtering_enabled" => "false"
    })
    |> render_submit()

    assert %{
             "meters_between_routes" => "900",
             "fog_of_war_meters" => "250",
             "gps_filtering_enabled" => false
           } = stored(c.id)

    c.view |> element("#native-settings-reset") |> render_click()
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

    c.view |> element("#native-recalculate") |> render_click()
    assert has_element?(c.view, "#native-settings-notice", "Recalculation queued")
    c.view |> element("#native-recalculate") |> render_click()
    assert has_element?(c.view, "#native-map-settings [role=alert]")
    assert outbox(c.id, "users.recalculate_data") == 1

    c.view |> element("#native-reapply-anomalies") |> render_click()
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
