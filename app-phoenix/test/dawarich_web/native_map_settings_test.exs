defmodule DawarichWeb.NativeMapSettingsTest do
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
      """
    end
  end

  setup do
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    Ownership.put!(Repo, "command:transportation.user_reclassify", :oban)
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "map-ui-#{id}@dawarich.test",
      plan: 1,
      status: 1,
      settings: %{"timezone" => "UTC"}
    })

    Repo.query!("UPDATE users SET settings = settings || $2 WHERE id=$1", [
      id,
      %{"immich_url" => "https://immich.example.test", "immich_api_key" => "synthetic-ui-secret"}
    ])

    {:ok, view, _} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host, session: %{"user_id" => id})

    %{id: id, view: view}
  end

  test "transport changes take effect only after Apply", %{id: id, view: view} do
    before = stored(id)
    assert has_element?(view, "#native-transport-apply[disabled]")

    view
    |> element("#native-map-settings-form")
    |> render_change(%{
      "_target" => ["enabledTransportationModes"],
      "enabledTransportationModes" => ["walking", "cycling"]
    })

    assert has_element?(view, "#native-transport-apply:not([disabled])")
    assert has_element?(view, "[data-dirty-scope=transportation] summary", "")
    assert stored(id) == before
    assert reclassify(id) == 0

    view |> element("#native-transport-apply") |> render_click()

    assert stored(id)["enabled_transportation_modes"] == ["walking", "cycling"]
    assert reclassify(id) == 1
    assert has_element?(view, "#native-transport-apply[disabled]")

    assert_push_event(view, "map:settings", %{
      settings: %{"enabled_transportation_modes" => ["walking", "cycling"]}
    })
  end

  test "unsaved advanced drafts keep their typed values across later edits", %{view: view} do
    form = element(view, "#native-map-settings-form")

    draft = %{
      "metersBetweenRoutes" => "750",
      "minutesBetweenRoutes" => "30",
      "fogOfWarRadius" => "300"
    }

    render_change(form, Map.put(draft, "_target", ["metersBetweenRoutes"]))

    render_change(
      form,
      %{draft | "minutesBetweenRoutes" => "45"} |> Map.put("_target", ["minutesBetweenRoutes"])
    )

    assert has_element?(view, "input[name=metersBetweenRoutes][value='750']")
    assert has_element?(view, "input[name=minutesBetweenRoutes][value='45']")
    assert has_element?(view, "input[name=fogOfWarRadius][value='300']")
  end

  test "save refusal leaves server settings unchanged", %{id: id, view: view} do
    before = stored(id)

    view
    |> element("#native-map-settings-form")
    |> render_change(%{
      "_target" => ["vectorTilesUrl"],
      "vectorTilesUrl" => "javascript:alert(1)"
    })

    assert_push_event(view, "map:toast", %{type: :error, key: "settings.invalid_tile_url"})
    assert stored(id) == before
    refute_push_event(view, "map:settings", %{})

    view
    |> element("#native-map-settings-form")
    |> render_change(%{
      "_target" => ["vectorTilesUrl"],
      "vectorTilesUrl" => "https://tiles.example.test/{z}/{x}/{y}.png"
    })

    assert stored(id)["maps_maplibre_tiles_url"] == "https://tiles.example.test/{z}/{x}/{y}.png"

    assert_push_event(view, "map:settings", %{settings: pushed})
    assert pushed["maps_maplibre_tiles_url"] == "https://tiles.example.test/{z}/{x}/{y}.png"
    assert pushed["immich_url"] == "https://immich.example.test"
    refute inspect(pushed) =~ "synthetic-ui-secret"
    refute render(view) =~ "synthetic-ui-secret"
    refute inspect(:sys.get_state(view.pid), limit: :infinity) =~ "synthetic-ui-secret"
  end

  defp stored(id), do: rows("SELECT settings FROM users WHERE id=$1", [id]) |> hd() |> hd()

  defp reclassify(id),
    do:
      rows(
        "SELECT count(*) FROM public.job_outbox WHERE command_type='transportation.user_reclassify' AND aggregate_id=$1",
        [id]
      )
      |> hd()
      |> hd()

  test "native live mode save shows its description and persisted state notice", %{
    view: view,
    id: id
  } do
    assert has_element?(view, "#native-map-settings-form", "Show new points in real-time")

    for {enabled, key} <- [{false, "live_map.disabled"}, {true, "live_map.enabled"}] do
      view |> element("[phx-click='settings:live']") |> render_click()

      assert stored(id)["live_map_enabled"] == enabled
      assert_push_event(view, "map:toast", %{type: :info, key: ^key})
    end
  end
end
