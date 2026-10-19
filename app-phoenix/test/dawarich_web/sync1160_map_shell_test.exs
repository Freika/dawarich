defmodule DawarichWeb.Sync1160MapShellTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  defp user do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "map-shell-#{id}@example.invalid",
      settings: %{"timezone" => "UTC", "enabled_map_layers" => ["Points", "Tracks"]}
    })

    id
  end

  defp open(id, path),
    do: RailsUser.signed_in(id) |> RailsUser.connecting_as(id) |> get(path) |> live()

  defp config(view) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query("#native-map")
    |> LazyHTML.attribute("data-map-config")
    |> hd()
    |> Jason.decode!()
  end

  test "all map locales render layer descriptions and place filters without removed keys" do
    id = user()

    Repo.query!("UPDATE users SET settings=settings || $2 WHERE id=$1", [
      id,
      %{"enabled_map_layers" => ["Points", "Visits", "Places", "Fog of War"]}
    ])

    for locale <- ~w(en ca de es fr pl zh) do
      {:ok, view, html} = open(id, "/map/v2?panel=layers&locale=" <> locale)

      missing =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query(
          "#native-map-layers .translation_missing, #native-map-controls > nav .translation_missing"
        )
        |> LazyHTML.attribute("title")

      assert missing == []

      assert has_element?(
               view,
               "#native-map-layers input[name='place_tag_ids[]'][value=untagged]"
             )

      assert has_element?(view, "#native-map-visit-filter")
      assert has_element?(view, "#visits-search[form=native-map-visit-filter]")
    end
  end

  test "Family panel requires current membership and disappears on removal while Tools keeps its action" do
    id = user()
    {:ok, view, _} = open(id, "/map/v2?panel=layers")
    refute has_element?(view, "[data-testid=map-button-family]")
    assert has_element?(view, "[data-testid=map-button-create][aria-label=Tools]")

    [[family]] =
      Repo.query!(
        "INSERT INTO families(name,creator_id,created_at,updated_at) VALUES('Synthetic',$1,now(),now()) RETURNING id",
        [id]
      ).rows

    Repo.query!(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,1,now(),now())",
      [family, id]
    )

    render_patch(view, "/map/v2?panel=family")
    assert has_element?(view, "[data-testid=map-button-family]")
    assert has_element?(view, "#native-map-family-panel a[href='/family']")
    assert has_element?(view, "#native-family-members")
    refute has_element?(view, "#native-map-layers input[value='Family Members']")
    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [id])
    send(view.pid, {:domain_changed, id, :membership})
    refute has_element?(view, "[data-testid=map-button-family]")
    refute has_element?(view, "#native-map-family-panel")
    assert config(view)["familyEnabled"] == false
  end

  test "layer panel groups fog modes retains visit filters and gates flights",
    do: layer_controls()

  defp layer_controls do
    id = user()
    {:ok, view, _} = open(id, "/map/v2?panel=layers")

    assert has_element?(
             view,
             "#native-map-layers input[name=fogOfWarMode][value=points][checked]"
           )

    refute has_element?(view, "[data-map-layer=flights]")

    render_hook(view, "settings:map_layers", %{
      "layers" => ["Points", "Visits", "Fog of War"],
      "fog_mode" => "hexagons"
    })

    assert config(view)["fogMode"] == "hexagons"

    assert has_element?(
             view,
             "#native-map-layers input[name=fogOfWarMode][value=hexagons][checked]"
           )

    refute has_element?(
             view,
             "#native-map-layers .layer-options__group:has(#visits-search)[style]"
           )

    view
    |> element("#native-map-visit-filter")
    |> render_change(%{"query" => "🏖️", "status" => "confirmed"})

    assert config(view)["visitFilter"] == %{"query" => "🏖️", "status" => "confirmed"}

    Repo.query!("UPDATE users SET settings=settings || $2 WHERE id=$1", [
      id,
      %{"airtrail_url" => "https://flights.example.invalid"}
    ])

    render_patch(view, "/map/v2?panel=layers&date=2026-01-01")
    assert has_element?(view, "[data-map-layer=flights]")
    assert config(view)["flightsEnabled"] == true
  end

  test "anomalies preference survives hiding points and native parameter refresh" do
    id = user()
    {:ok, view, _} = open(id, "/map/v2?panel=layers")
    render_click(view, "map:anomalies", %{"enabled" => "true"})
    assert config(view)["anomaliesEnabled"] == true
    render_hook(view, "settings:map_layers", %{"layers" => ["Tracks"]})
    assert config(view)["anomaliesEnabled"] == false
    assert has_element?(view, "[data-map-layer=anomalies][checked]")
    render_hook(view, "settings:map_layers", %{"layers" => ["Points", "Tracks"]})
    assert config(view)["anomaliesEnabled"] == true
    render_patch(view, "/map/v2?panel=layers&date=2026-01-01")
    assert config(view)["anomaliesEnabled"] == true
  end
end
