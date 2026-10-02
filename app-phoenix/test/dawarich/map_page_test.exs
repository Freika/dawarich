defmodule Dawarich.MapPageTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.{MapPage, Repo}
  alias Dawarich.Test.{MapSeeds, RailsUser}

  @now ~U[2026-09-29 10:00:00Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    System.put_env("JWT_SECRET_KEY", "phoenix-a6-jwt-fixture-secret-not-for-production")
    System.put_env("MANAGER_URL", "https://manager.a6-fixture.test")

    for key <- ~w(PHOTON_API_HOST GEOAPIFY_API_KEY NOMINATIM_API_HOST LOCATIONIQ_API_KEY),
        do: System.delete_env(key)

    on_exit(fn -> Enum.each(~w(JWT_SECRET_KEY MANAGER_URL), &System.delete_env/1) end)
  end

  @opts [now: ~U[2026-09-29 10:00:00Z], self_hosted: true, family: true, env: %{}]

  defp load(name, params \\ nil) do
    state = MapSeeds.load(name)
    user = MapSeeds.seed!(state)

    MapPage.load(user, params || state["params"],
      now: @now,
      self_hosted: state["self_hosted"],
      family: true,
      env: %{}
    )
  end

  test "a self-hosted Pro user: key, plan, links, defaults" do
    {:ok, page} = load("self_hosted_en")
    assert {page.api_key, page.plan, page.full_access} == {"a6-k-6101", "pro", true}
    assert {page.upgrade_url, page.badge_url} == {"", ""}
    assert page.features_json == ~s({"reverse_geocoding":false,"family":true})

    assert {page.live_map, page.fog_mode, page.transport_modes} ==
             {true, "points", MapPage.modes()}

    assert {page.place, page.import_id, page.tags, page.live_share, page.demo_data} ==
             {nil, nil, [], false, false}

    assert page.window.start == "2026-09-20T00:00:00+02:00"
  end

  test "settings: live mode off, hexagons, a modes subset, AirTrail, Immich, the eight rail tags" do
    {:ok, page} = load("timeline_en")

    assert {page.live_map, page.fog_mode, page.airtrail, page.immich} ==
             {false, "hexagons", true, true}

    assert page.transport_modes == ~w(walking cycling train)

    assert {page.hidden_tile_categories, page.disabled_poi_groups} ==
             {["buildings"], ["shopping"]}

    assert length(page.tags) == 9
    assert Enum.map(page.timeline_tags, & &1.name) == Enum.map(Enum.take(page.tags, 8), & &1.name)
    assert page.timezone == "Europe/Berlin"
  end

  test "the drawer place comes from lonlat; a numeric prefix finds it; another user's is not found" do
    {:ok, page} = load("place_import_en")
    assert page.place == %{id: 6150, lat: 52.520008, lon: 13.404954}
    assert page.import_id == 6160
    assert page.window.start == "2026-01-01T00:00:00+05:30"

    assert {:ok, %{place: %{id: 6150}}} =
             MapPage.load(Dawarich.Accounts.get(6103), %{"place_id" => "6150abc"}, @opts)

    other =
      Dawarich.Accounts.get(RailsUser.insert!(%{id: 6099, email: "a6-other@dawarich.test"}).id)

    for id <- ["6150", "abc", "-1", "99999999999999999999"],
        do: assert(MapPage.load(other, %{"place_id" => id}, @opts) == :not_found, id)

    assert {:ok, %{place: nil}} = MapPage.load(other, %{"place_id" => "  "}, @opts)
  end

  test "a legacy place without lonlat uses its latitude and longitude columns" do
    {:ok, page} = load("legacy_place_en")
    assert page.place == %{id: 6151, lat: 48.1371, lon: 11.5754}
  end

  test "Cloud Lite: restricted, upgrade links, Lite's map categories dropped, live share and demo data" do
    {:ok, page} = load("cloud_lite_en")
    assert {page.plan, page.full_access} == {"lite", false}

    assert page.upgrade_url =~
             ~r{\Ahttps://manager\.a6-fixture\.test/auth/dawarich\?token=[^&]+&utm_campaign=lite_upgrade&utm_content=maplibre&utm_medium=map&utm_source=app\z}

    assert page.badge_url =~
             ~r{&utm_campaign=lite_upgrade&utm_content=pro_badge&utm_medium=badge&utm_source=app\z}

    assert {page.hidden_tile_categories, page.live_share, page.demo_data} == {[], true, true}
  end

  test "a Lite member of a live Family owner's family is on the family plan" do
    owner =
      RailsUser.insert!(%{
        id: 6097,
        email: "a6-owner@dawarich.test",
        plan: 2,
        active_until: ~N[3026-01-01 00:00:00]
      })

    member = RailsUser.insert!(%{id: 6098, email: "a6-member@dawarich.test", plan: 0})
    stamp = NaiveDateTime.utc_now(:second)

    {1, [%{id: family}]} =
      Repo.insert_all(
        "families",
        [%{name: "F", creator_id: owner.id, created_at: stamp, updated_at: stamp}],
        returning: [:id]
      )

    Repo.insert_all("family_memberships", [
      %{family_id: family, user_id: member.id, role: 1, created_at: stamp, updated_at: stamp}
    ])

    {:ok, page} =
      MapPage.load(Dawarich.Accounts.get(member.id), %{},
        now: @now,
        self_hosted: false,
        family: true,
        env: %{}
      )

    assert {page.plan, page.full_access} == {"family", true}
  end

  test "Ruby include? on arrays and strings" do
    assert MapPage.member?(["roads"], "roads")
    assert MapPage.member?("roads,rail", "rail")
    refute MapPage.member?(%{"roads" => true}, "roads")
  end

  @tag :tmp_dir
  test "poster themes are the sorted JSON files; broken ones are skipped", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "b.json"), ~s({"name":"Bee"}))
    File.write!(Path.join(dir, "a.json"), ~s({"name":"Ant"}))
    File.write!(Path.join(dir, "c.json"), "{")
    assert MapPage.read_themes(dir) == [%{key: "a", name: "Ant"}, %{key: "b", name: "Bee"}]
  end
end
