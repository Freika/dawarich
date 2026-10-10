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

  test "native sharing dialog selects and revokes the owned card", %{user: user} do
    progress(%{"earned" => %{"DE-BY" => "2026-07-19T10:00:00Z"}})
    {:ok, view, _html} = live_as(user, "/achievements/country_de")
    render_click(view, "select_card", %{"key" => "country_de"})
    assert has_element?(view, "#achievement-dialog [data-selected-key=country_de]")
    render_click(view, "share_card", %{"enabled" => "true"})
    assert has_element?(view, "#achievement-share-output[value*='/shared/achievements/']")
    render_click(view, "share_card", %{"enabled" => "false"})
    refute has_element?(view, "#achievement-share-output")
  end

  test "native collection renders and connects with missing exploration untouched", %{user: user} do
    {:ok, view, html} = live_as(user, "/achievements")
    assert html =~ "data-phx-main" and html =~ "achievement-collection"
    assert has_element?(view, ".ach-getting-started a[href='/imports/new']")
    assert has_element?(view, "a[data-phx-link=patch][href='/achievements']")

    assert [[0]] =
             Dawarich.Repo.query!(
               "SELECT count(*) FROM achievement_progresses WHERE user_id=$1",
               [user.id]
             ).rows

    refute html =~ "data-controller="
    assert html =~ ~s(phx-hook="AchievementUnlocks")
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

      assert Enum.count(LazyHTML.query(actual, "#native-achievements .ach-grid button")) == 13

      assert LazyHTML.query(actual, ".ach-page .ach-silhouette-svg path")
             |> LazyHTML.attribute("d") ==
               LazyHTML.query(expected, ".ach-silhouette-svg path") |> LazyHTML.attribute("d")

      assert has_element?(view, "#achievement-filter[phx-submit=filter] input[maxlength='100']")
      render_click(view, "select_card", %{"key" => "country_de"})
      assert has_element?(view, "#achievement-dialog [data-selected-key=country_de]")
      assert has_element?(view, "a[rel=next][data-phx-link=patch]")
      assert has_element?(view, "a[href='/achievements/continent_europe']")
      assert Enum.count(LazyHTML.query(actual, "meta[name='csrf-token']")) == 1
    end
  end

  test "static achievement read stays unseen and connected acknowledgement is once only", %{
    user: user
  } do
    fixture = File.read!(Path.join(@root, "en-complete-first.json")) |> Jason.decode!()
    progress(fixture["seed_state"])
    {:ok, first, _} = live_as(user, "/achievements/country_de")
    assert has_element?(first, "[data-celebrate=true]")

    assert [[stamp]] =
             Dawarich.Repo.query!(
               "SELECT state->'celebrated'->>'country_de' FROM achievement_progresses WHERE user_id=$1",
               [user.id]
             ).rows

    assert {:ok, _, offset} = DateTime.from_iso8601(stamp)
    assert offset == 7200

    {:ok, second, _} = live_as(user, "/achievements/country_de")
    refute has_element?(second, "[data-celebrate=true]")
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

  test "native filter submission keeps unlocked region values through connection", %{user: user} do
    progress(%{"earned" => %{"DE" => "2026-07-01T10:00:00Z", "DE-BY" => "2026-07-01T10:00:00Z"}})
    {:ok, view, _} = live_as(user, "/achievements/country_de")
    render_submit(view, "filter", %{"q" => "", "status" => "unlocked"})
    assert has_element?(view, "#achievement-status option[value=unlocked][selected]")

    assert :sys.get_state(view.pid).socket.assigns.data.view.children |> Enum.map(& &1["name"]) ==
             ["Bavaria"]

    conn =
      RailsUser.signed_in(user.id)
      |> RailsUser.connecting_as(user.id)
      |> get("/achievements/country_de?status=unlocked")

    {:ok, connected, _} = live(conn)
    assert has_element?(connected, ".card-title", "Bavaria")
    assert length(:sys.get_state(connected.pid).socket.assigns.data.view.children) == 1
  end

  test "native URL paging escaping and no-results retain the source filters", %{user: user} do
    progress(%{"earned" => %{"DE" => "2026-07-19T10:00:00Z"}})

    {:ok, view, html} =
      live_as(user, "/achievements/continent_europe?q=%3Cscript%3E&status=locked")

    assert has_element?(view, "#native-achievements p[role=status]")
    assert has_element?(view, "input[name='q'][value='<script>']")
    refute html =~ "<script>"
    assert has_element?(view, "#achievement-filter a[data-phx-link=patch]")
  end
end
