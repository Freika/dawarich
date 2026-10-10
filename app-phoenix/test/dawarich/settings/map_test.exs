defmodule Dawarich.Settings.MapTest do
  use Dawarich.DataCase, async: false
  alias Dawarich.{Accounts, Maps}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Settings.Map, as: MapSettings
  alias Dawarich.Test.RailsUser

  @now ~U[2026-10-10 10:00:00Z]
  @layers ["Points", "Heatmap", "Routes"]
  @attrs %{
    "enabled_map_layers" => @layers,
    "globe_projection" => true,
    "minutes_between_routes" => "5000",
    "maps" => %{"hidden_tile_categories" => ["poi"], "distance_unit" => "mi"}
  }

  setup do
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    Ownership.put!(Repo, "command:transportation.user_reclassify", :oban)
    :ok
  end

  test "Lite settings preserve forbidden categories and native casts" do
    lite = Maps.principal(account!(0), "en")
    pro = Maps.principal(account!(1), "en")

    assert {:ok, %{settings: settings, recalculation_triggered: false}} =
             MapSettings.update(lite, @attrs, now: @now, self_hosted?: false)

    assert settings["enabled_map_layers"] == ["Points", "Tracks"]
    assert settings["globe_projection"] == false
    assert settings["minutes_between_routes"] == 1440
    assert settings["distance_unit"] == "mi"
    refute Map.has_key?(settings["maps"], "hidden_tile_categories")
    assert stored(lite)["enabled_map_layers"] == ["Points", "Routes"]
    assert {:ok, ^settings} = MapSettings.get(lite, now: @now, self_hosted?: false)

    assert {:ok, %{settings: full}} =
             MapSettings.update(pro, @attrs, now: @now, self_hosted?: false)

    assert full["enabled_map_layers"] == ["Points", "Heatmap", "Tracks"]
    assert full["maps"]["hidden_tile_categories"] == ["poi"]
    assert full["globe_projection"] == true
  end

  test "recalculation refuses revoked scope before durable enqueue" do
    user = account!(1)
    scope = Maps.principal(user, "en")
    before = stored(scope)

    rows("UPDATE users SET encrypted_password=$1 WHERE id=$2", [
      String.duplicate("rotated", 10),
      user.id
    ])

    attrs = %{"enabled_transportation_modes" => ["walking"]}

    assert {:error, :stale_session} =
             MapSettings.update(scope, attrs, now: @now, self_hosted?: true)

    assert {:error, :stale_session} =
             MapSettings.recalculation(scope, now: @now, self_hosted?: true)

    assert stored(scope) == before
    assert reclassify(user) == 0

    fresh = Maps.principal(Accounts.get(user.id), "en")

    assert {:ok, %{recalculation_triggered: true}} =
             MapSettings.update(fresh, attrs, now: @now, self_hosted?: true)

    assert reclassify(user) == 1

    assert {:ok, %{"status" => _}} =
             MapSettings.recalculation(fresh, now: @now, self_hosted?: true)
  end

  test "invalid tile URL is a typed refusal that leaves settings unchanged" do
    scope = Maps.principal(account!(1), "en")
    before = stored(scope)

    assert {:error, {:invalid, [_]}} =
             MapSettings.update(scope, %{"maps_maplibre_tiles_url" => "javascript:alert(1)"},
               now: @now,
               self_hosted?: true
             )

    assert stored(scope) == before
  end

  test "map settings never return provider credentials" do
    user = account!(1)

    Repo.query!("UPDATE users SET settings = settings || $2 WHERE id=$1", [
      user.id,
      %{
        "immich_url" => "https://immich.example.test",
        "immich_api_key" => "synthetic-immich-secret",
        "photoprism_url" => "https://photoprism.example.test",
        "photoprism_api_key" => "synthetic-photoprism-secret",
        "airtrail_url" => "https://airtrail.example.test",
        "airtrail_api_key" => "synthetic-airtrail-secret"
      }
    ])

    scope = Maps.principal(Accounts.get(user.id), "en")
    {:ok, read} = MapSettings.get(scope, now: @now, self_hosted?: true)

    {:ok, saved} =
      MapSettings.update(scope, %{"route_opacity" => "0.5"}, now: @now, self_hosted?: true)

    serialized = inspect({read, saved}, limit: :infinity)
    refute serialized =~ "synthetic-"
    assert read["immich_url"] == "https://immich.example.test"
  end

  defp stored(scope),
    do: rows("SELECT settings FROM users WHERE id=$1", [scope.user.id]) |> hd() |> hd()

  defp reclassify(user),
    do:
      rows(
        "SELECT count(*) FROM public.job_outbox WHERE command_type='transportation.user_reclassify' AND aggregate_id=$1",
        [user.id]
      )
      |> hd()
      |> hd()

  defp account!(plan) do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "map-settings-#{id}@dawarich.test",
      api_key: Ecto.UUID.generate(),
      plan: plan,
      status: 1,
      settings: %{"timezone" => "UTC"}
    })

    Accounts.get(id)
  end
end
