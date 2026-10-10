defmodule DawarichWeb.DigestsLiveTest do
  use ExUnit.Case, async: false

  import Dawarich.Test.StatsSeeds
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.Test.RailsUser

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    for key <- ~w(SELF_HOSTED JWT_SECRET_KEY), do: System.delete_env(key)

    user =
      RailsUser.insert!(%{
        id: 5801,
        email: "a5s-dl@dawarich.test",
        settings: %{"timezone" => "Europe/Berlin", "maps" => %{"distance_unit" => "km"}}
      })

    %{user: user}
  end

  defp live_as(user, path),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  defp full_digest(user_id, year),
    do:
      digest!(user_id, %{
        year: year,
        distance: 50_000,
        toponyms: [toponym("Germany", ["Berlin"]), toponym("Czechia", ["Prague"])],
        first_time_visits: %{"countries" => ["Czechia"], "cities" => ["Prague"]},
        year_over_year: %{"distance_change_percent" => 150, "previous_year" => year - 1},
        all_time_stats: %{"total_countries" => 2, "total_cities" => 2, "total_distance" => 70_000},
        monthly_distances: %{"3" => 38_400, "4" => 11_600}
      })

  test "the index lists past digests newest first with Rails' totals, and hides the unfinished year",
       %{user: user} do
    full_digest(user.id, 2024)

    digest!(user.id, %{
      year: 2023,
      distance: 20_000,
      toponyms: [toponym("Germany", ["Berlin"])],
      first_time_visits: %{"countries" => ["Germany"], "cities" => ["Berlin"]}
    })

    digest!(user.id, %{year: Date.utc_today().year, distance: 1000})
    {:ok, view, html} = live_as(user, "/digests")
    assert html =~ ">Year-End Digests | Dawarich</title>"

    assert html
           |> LazyHTML.from_document()
           |> LazyHTML.query("h2.card-title > a")
           |> Enum.map(&LazyHTML.text/1) == ["2024", "2023"]

    assert has_element?(view, ~s(a.btn[href="/digests/2024"]), "View Details")
    assert has_element?(view, ".stat-value.text-primary", "50 km")
    refute has_element?(view, "label.btn", "Generate Digest")
  end

  test "generation links are Rails' POST method links for available years, for active users only",
       %{user: user} do
    stat!(user.id, %{year: 2022, month: 5})
    {:ok, view, _html} = live_as(user, "/digests")
    assert has_element?(view, ~s(a[data-turbo-method="post"][href="/digests?year=2022"]), "2022")
    assert render(view) =~ "Or you can manually generate one for a previous year."
    Dawarich.Repo.query!("UPDATE users SET status = 0 WHERE id = $1", [user.id])
    {:ok, inactive, _html} = live_as(user, "/digests")
    refute has_element?(inactive, "a[data-turbo-method]")
    refute render(inactive) =~ "Or you can manually generate"
    assert has_element?(inactive, "h2", "No Year-End Digests Yet")
  end

  test "a digest shows the full review with access, and the upgrade card for Lite on Cloud", %{
    user: user
  } do
    full_digest(user.id, 2024)
    {:ok, view, html} = live_as(user, "/digests/2024")
    assert html =~ ">2024 Year in Review | Dawarich</title>"
    assert has_element?(view, "p", "That's 0.1% of Earth's circumference!")
    assert has_element?(view, "p.positive", "+150% compared to 2023")
    assert has_element?(view, "#chart-1[phx-update='ignore']")
    assert has_element?(view, ".card-title", "All-Time Stats")
    System.put_env("SELF_HOSTED", "false")
    System.put_env("JWT_SECRET_KEY", "phoenix-a5-jwt-fixture-secret-not-for-production")
    on_exit(fn -> for key <- ~w(SELF_HOSTED JWT_SECRET_KEY), do: System.delete_env(key) end)
    Dawarich.Repo.query!("UPDATE users SET plan = 0 WHERE id = $1", [user.id])
    {:ok, lite, _html} = live_as(user, "/digests/2024")
    refute has_element?(lite, "#chart-1")
    refute has_element?(lite, ".card-title", "All-Time Stats")
    assert has_element?(lite, ~s(a.btn-primary[href*="utm_content=year_in_review"]))
  end

  test "a missing or foreign digest redirects to /digests with Rails' alert", %{user: user} do
    other = RailsUser.insert!(%{id: 5802, email: "a5s-dl2@dawarich.test"})
    full_digest(other.id, 2024)

    assert {:error, {:redirect, %{to: "/digests", flash: %{"alert" => "Digest not found"}}}} =
             live_as(user, "/digests/2024")
  end

  test "delete is Rails' button_to DELETE form with the turbo confirmation; sharing posts to Rails",
       %{user: user} do
    full_digest(user.id, 2023)
    {:ok, view, _html} = live_as(user, "/digests/2023")

    assert has_element?(
             view,
             ~s(form.button_to[method="post"][action="/digests/2023"] input[name="_method"][value="delete"])
           )

    assert has_element?(
             view,
             ~s(form.button_to button[data-turbo-confirm="Are you sure you want to delete the 2023 digest? This cannot be undone."])
           )

    assert has_element?(
             view,
             ~s(#sharing_modal[phx-hook="RailsStimulus"] form[action="/digests/2023/sharing"] option[value="24h"][selected="selected"])
           )

    assert has_element?(view, ~s(a.btn[href="/digests"]), "Back to All Digests")
  end

  test "the monthly chart uses German month abbreviations for a German user", %{user: user} do
    Dawarich.Repo.query!(
      ~s(UPDATE users SET settings = settings || '{"locale": "de"}' WHERE id = $1),
      [user.id]
    )

    full_digest(user.id, 2024)
    html = RailsUser.signed_in(user.id) |> get("/digests/2024") |> html_response(200)
    assert html =~ ~s([["Mär",38],["Apr",12]])
  end
end
