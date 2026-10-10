defmodule DawarichWeb.AchievementsLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint
  @root Path.expand("../fixtures/achievements_ui", __DIR__)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    Dawarich.Test.AchievementSilhouettes.clear()
    on_exit(&Dawarich.Test.AchievementSilhouettes.clear/0)
    prior = Application.fetch_env(:dawarich, :achievement_ui_now)
    Application.put_env(:dawarich, :achievement_ui_now, fn -> ~U[2026-07-19 10:00:00Z] end)

    on_exit(fn ->
      case prior do
        {:ok, value} -> Application.put_env(:dawarich, :achievement_ui_now, value)
        :error -> Application.delete_env(:dawarich, :achievement_ui_now)
      end
    end)

    user =
      RailsUser.insert!(%{
        id: 79201,
        email: "a10-live@example.test",
        settings: %{"timezone" => "Europe/Berlin", "locale" => "en"}
      })

    Dawarich.Repo.query!(
      "INSERT INTO countries(iso_a2,iso_a3,name,geom,created_at,updated_at) VALUES('DE','DEU','Germany',ST_GeomFromText('MULTIPOLYGON (((12.25 51.25,12.25 51.5,12.5 51.5,12.5 51.25,12.25 51.25)))',4326),now(),now()),('FR','FRA','France',ST_GeomFromText('MULTIPOLYGON (((12.5 51.25,12.5 51.375,12.625 51.375,12.625 51.25,12.5 51.25)))',4326),now(),now())"
    )

    Dawarich.Repo.query!(
      "INSERT INTO regions(code,geom,created_at,updated_at) VALUES('DE-BY',ST_GeomFromText('MULTIPOLYGON (((12.25 51.25,12.25 51.5,12.5 51.5,12.5 51.25,12.25 51.25)))',4326),now(),now())"
    )

    %{user: user}
  end

  defp progress(state) do
    Dawarich.Repo.query!(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES(79201,'exploration',$1,now(),now())",
      [state]
    )
  end

  defp live_as(user, path),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  test "sharing controls and the open card modal stay in one browser owned island", %{user: user} do
    progress(%{"earned" => %{"DE-BY" => "2026-07-19T10:00:00Z"}})
    {:ok, view, _html} = live_as(user, "/achievements/country_de")
    island = "#phx-achievements[phx-update='ignore']"
    assert has_element?(view, island <> " dialog.ach-modal")

    for target <- ~w(featured createForm disableForm publicLink) do
      assert has_element?(view, island <> " [data-card-modal-target='#{target}']")
    end
  end

  test "native collection renders and connects with missing exploration untouched", %{user: user} do
    {:ok, view, html} = live_as(user, "/achievements")
    assert html =~ "data-phx-main" and html =~ "achievement-collection"
    assert has_element?(view, ".ach-getting-started a[href='/imports/new']")
    assert has_element?(view, ".ach-side--desktop .ach-side-link--active[href='/achievements']")

    assert [[0]] =
             Dawarich.Repo.query!(
               "SELECT count(*) FROM achievement_progresses WHERE user_id=$1",
               [user.id]
             ).rows

    assert html =~ ~s(data-controller="achievement-unlocks")
  end

  for locale <- ["en", "de"] do
    test "#{locale} detail has bounded source cards/filter/modal/sharing controls", %{user: user} do
      fixture =
        File.read!(Path.join(@root, unquote(locale) <> "-detail-progress.json"))
        |> Jason.decode!()

      progress(fixture["seed_state"])

      Dawarich.Repo.query!("UPDATE users SET settings=settings||$2 WHERE id=$1", [
        user.id,
        %{"locale" => unquote(locale)}
      ])

      {:ok, view, html} = live_as(user, "/achievements/country_de")

      expected =
        File.read!(Path.join(@root, unquote(locale) <> "-detail-progress.html"))
        |> LazyHTML.from_fragment()

      actual = LazyHTML.from_document(html)

      for selector <- [
            ".card-title",
            ".card-description",
            ".earned span",
            ".metric span",
            ".rarity",
            ".ach-threshold-note"
          ] do
        assert Enum.map(
                 LazyHTML.query(actual, ".ach-page " <> selector),
                 &(LazyHTML.text(&1) |> String.trim())
               ) ==
                 Enum.map(
                   LazyHTML.query(expected, selector),
                   &(LazyHTML.text(&1) |> String.trim())
                 )
      end

      assert Enum.count(LazyHTML.query(actual, ".ach-child-grid .ach-card-wrap")) == 12

      assert LazyHTML.query(actual, ".ach-page .ach-silhouette-svg path")
             |> LazyHTML.attribute("d") ==
               LazyHTML.query(expected, ".ach-silhouette-svg path") |> LazyHTML.attribute("d")

      assert has_element?(
               view,
               "form.ach-collection-toolbar[method='get'] input[maxlength='100']"
             )

      assert has_element?(
               view,
               "form[action='/achievements/country_de/toggle_sharing'] input[name='_method'][value='patch']"
             )

      assert has_element?(view, "dialog.ach-modal [data-card-modal-target='stage']")
      assert has_element?(view, ".ach-collection-pager a[rel='next']")
      assert has_element?(view, ".ach-pagination a[rel='next'][href*='#collection']")
      assert has_element?(view, ".ach-side-link--active[href='/achievements/continent_europe']")
      assert Enum.count(LazyHTML.query(actual, "meta[name='csrf-token']")) == 1
    end
  end

  test "first GET celebration survives connected mount and second GET clears it", %{user: user} do
    fixture = File.read!(Path.join(@root, "en-complete-first.json")) |> Jason.decode!()
    progress(fixture["seed_state"])
    {:ok, first, _} = live_as(user, "/achievements/country_de")
    assert has_element?(first, ".ach-set-preview .ach-card-wrap--celebrate")

    assert [["2026-07-19T12:00:00+02:00"]] =
             Dawarich.Repo.query!(
               "SELECT state->'celebrated'->>'country_de' FROM achievement_progresses WHERE user_id=$1",
               [user.id]
             ).rows

    {:ok, second, _} = live_as(user, "/achievements/country_de")
    refute has_element?(second, ".ach-card-wrap--celebrate")
  end

  test "the connected mount reuses the silhouettes the first render built", %{user: user} do
    progress(%{"earned" => %{"DE-BY" => "2026-07-19T10:00:00Z"}})

    conn =
      RailsUser.signed_in(user.id)
      |> RailsUser.connecting_as(user.id)
      |> get("/achievements/country_de")

    first = paths(html_response(conn, 200))

    wide =
      "ST_GeomFromText('MULTIPOLYGON (((12.125 51.125,12.125 51.5,12.75 51.5,12.75 51.125,12.125 51.125)))',4326)"

    Dawarich.Repo.query!("UPDATE countries SET geom=#{wide}")
    Dawarich.Repo.query!("UPDATE regions SET geom=#{wide}")
    {:ok, view, _html} = live(conn)

    assert paths(render(view)) == first
  end

  defp paths(html),
    do:
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query(".ach-silhouette-svg path")
      |> LazyHTML.attribute("d")

  test "GET form serialization keeps unlocked region filters through connection", %{
    user: user
  } do
    progress(%{
      "earned" => %{"DE" => "2026-07-01T10:00:00Z", "DE-BY" => "2026-07-01T10:00:00Z"}
    })

    conn =
      RailsUser.signed_in(user.id)
      |> RailsUser.connecting_as(user.id)
      |> get("/achievements/country_de")

    html = html_response(conn, 200)
    form = LazyHTML.from_document(html) |> LazyHTML.query("form.ach-collection-toolbar")
    assert LazyHTML.attribute(form, "method") == ["get"]

    assert LazyHTML.query(form, "select[name='status'] option[selected]")
           |> LazyHTML.attribute("value") == ["all"]

    {:ok, initial, _} = live(conn)
    assert has_element?(initial, "select[name='status'] option[value='all'][selected]")

    params =
      form
      |> LazyHTML.query("input[name], select[name]")
      |> Enum.map(fn control ->
        [name] = LazyHTML.attribute(control, "name")

        value =
          if name == "status",
            do: "unlocked",
            else: control |> LazyHTML.attribute("value") |> List.first("")

        {name, value}
      end)
      |> Map.new()

    assert params == %{"q" => "", "status" => "unlocked", "commit" => "Apply"}
    [action] = LazyHTML.attribute(form, "action")
    target = URI.parse(action).path <> "?" <> URI.encode_query(params)

    filtered =
      RailsUser.signed_in(user.id)
      |> RailsUser.connecting_as(user.id)
      |> get(target)

    filtered_html = html_response(filtered, 200) |> LazyHTML.from_document()

    assert LazyHTML.query(filtered_html, ".ach-child-grid .card-title") |> LazyHTML.text() ==
             "Bavaria"

    assert LazyHTML.query(filtered_html, "select[name='status'] option[selected]")
           |> LazyHTML.attribute("value") == ["unlocked"]

    {:ok, view, _} = live(filtered)
    assert has_element?(view, ".ach-child-grid .card-title", "Bavaria")

    assert render(view)
           |> LazyHTML.from_document()
           |> LazyHTML.query(".ach-child-grid .card-title")
           |> Enum.count() == 1

    assert has_element?(view, "select[name='status'] option[value='unlocked'][selected]")
  end

  test "GET paging escaping and no-results reflect original filters", %{user: user} do
    progress(%{"earned" => %{"DE" => "2026-07-19T10:00:00Z"}})

    {:ok, view, html} =
      live_as(user, "/achievements/continent_europe?q=%3Cscript%3E&status=locked")

    assert has_element?(view, ".ach-empty[role='status']")
    assert has_element?(view, "input[name='q'][value='<script>']")
    refute html =~ "<script>"
    assert has_element?(view, "a[href='/achievements/continent_europe#collection']")
  end
end
