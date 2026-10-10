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

  test "native generation retains available years source notices and active account policy",
       %{user: user} do
    stat!(user.id, %{year: 2022, month: 5})
    {:ok, view, _html} = live_as(user, "/digests")
    assert has_element?(view, ~s(button[phx-click="generate"][phx-value-year="2022"]), "2022")
    assert render(view) =~ "Or you can manually generate one for a previous year."
    render_click(view, "generate", %{"year" => "2022"})
    assert render(view) =~ "2022 is being generated"

    assert Dawarich.Repo.query!(
             "SELECT count(*) FROM public.job_outbox WHERE command_type='digests.calculate_year'",
             [],
             log: false
           ).rows == [[1]]

    Dawarich.Repo.query!("UPDATE users SET status = 0 WHERE id = $1", [user.id])
    {:ok, inactive, _html} = live_as(user, "/digests")
    refute has_element?(inactive, "button[phx-click=generate]")
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
    assert has_element?(view, "#digest-monthly-chart[phx-hook=NativeChart]")
    assert has_element?(view, ".card-title", "All-Time Stats")
    System.put_env("SELF_HOSTED", "false")
    System.put_env("JWT_SECRET_KEY", "phoenix-a5-jwt-fixture-secret-not-for-production")
    on_exit(fn -> for key <- ~w(SELF_HOSTED JWT_SECRET_KEY), do: System.delete_env(key) end)
    Dawarich.Repo.query!("UPDATE users SET plan = 0 WHERE id = $1", [user.id])
    {:ok, lite, _html} = live_as(user, "/digests/2024")
    refute has_element?(lite, "#digest-monthly-chart")
    refute has_element?(lite, ".card-title", "All-Time Stats")
    assert has_element?(lite, "#digest-upgrade button[phx-click=upgrade]")
    render_click(lite, "upgrade", %{})
    assert_redirect(lite)
  end

  test "a missing or foreign digest redirects to /digests with Rails' alert", %{user: user} do
    other = RailsUser.insert!(%{id: 5802, email: "a5s-dl2@dawarich.test"})
    full_digest(other.id, 2024)

    assert {:error, {:redirect, %{to: "/digests", flash: %{"alert" => "Digest not found"}}}} =
             live_as(user, "/digests/2024")
  end

  test "native sharing auto-saves source expiry and delete cancellation has no effects", %{
    user: user
  } do
    full_digest(user.id, 2023)
    {:ok, view, _} = live_as(user, "/digests/2023")
    render_click(view, "delete", %{})
    assert has_element?(view, "#digest-delete-dialog[role=dialog]")
    render_click(view, "cancel_delete", %{})

    assert Dawarich.Repo.query!("SELECT year FROM digests WHERE user_id=$1", [user.id],
             log: false
           ).rows == [[2023]]

    render_click(view, "open_share", %{})
    assert has_element?(view, "#digest-share-dialog form[phx-change=share]")

    view
    |> form("#digest-share-dialog form", %{"share" => %{"enabled" => "1", "expiration" => "12h"}})
    |> render_change()

    [[settings, uuid]] =
      Dawarich.Repo.query!(
        "SELECT sharing_settings,sharing_uuid::text FROM digests WHERE user_id=$1",
        [user.id],
        log: false
      ).rows

    assert settings["enabled"]
    assert settings["expiration"] == "12h"
    assert has_element?(view, ~s(a[href$="/shared/digest/#{uuid}"]))
    render_click(view, "close_share", %{})
    render_click(view, "open_share", %{})
    assert has_element?(view, ~s(option[value="12h"][selected]))
    assert has_element?(view, ~s(a[href$="/shared/digest/#{uuid}"]))
    refute render(view) =~ "data-turbo"
    refute render(view) =~ "translation_missing"
    assert has_element?(view, ~s(a[href="/digests"]), "Back to All Digests")
  end

  test "the monthly chart uses German month abbreviations for a German user", %{user: user} do
    Dawarich.Repo.query!(
      ~s(UPDATE users SET settings = settings || '{"locale": "de"}' WHERE id = $1),
      [user.id]
    )

    full_digest(user.id, 2024)
    html = RailsUser.signed_in(user.id) |> get("/digests/2024") |> html_response(200)

    [raw] =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("#digest-monthly-chart")
      |> LazyHTML.attribute("data-chart")

    assert Jason.decode!(raw)["data"] == [["Mär", 38], ["Apr", 12]]
  end
end
