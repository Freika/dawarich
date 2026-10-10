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
      <DawarichWeb.NativeMapSettings.panel settings={@map_settings} locale="en" />
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

    {:ok, view, _} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host, session: %{"user_id" => id})

    %{id: id, view: view}
  end

  test "transport changes take effect only after Apply", %{id: id, view: view} do
    before = stored(id)
    assert has_element?(view, "#native-transport-apply[disabled]")

    view
    |> form("#native-transport-form", %{"modes" => ["walking", "cycling"]})
    |> render_change()

    assert has_element?(view, "#native-transport-apply:not([disabled])")
    assert stored(id) == before
    assert reclassify(id) == 0

    view
    |> form("#native-transport-form", %{"modes" => ["walking", "cycling"]})
    |> render_submit()

    assert stored(id)["enabled_transportation_modes"] == ["walking", "cycling"]
    assert reclassify(id) == 1
    assert has_element?(view, "#native-transport-apply[disabled]")

    assert_push_event(view, "map:settings", %{
      settings: %{"enabled_transportation_modes" => ["walking", "cycling"]}
    })
  end

  test "save refusal leaves server settings unchanged", %{id: id, view: view} do
    before = stored(id)

    html =
      view
      |> form("#native-appearance-form", %{"maps_maplibre_tiles_url" => "javascript:alert(1)"})
      |> render_submit()

    assert html =~ "Tile URL must include"
    assert stored(id) == before
    refute_push_event(view, "map:settings", %{})

    view
    |> form("#native-appearance-form", %{
      "maps_maplibre_tiles_url" => "https://tiles.example.test/{z}/{x}/{y}.png"
    })
    |> render_submit()

    assert stored(id)["maps_maplibre_tiles_url"] == "https://tiles.example.test/{z}/{x}/{y}.png"

    assert_push_event(view, "map:settings", %{
      settings: %{"maps_maplibre_tiles_url" => "https://tiles.example.test/{z}/{x}/{y}.png"}
    })
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
end
