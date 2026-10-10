defmodule DawarichWeb.InsightsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.Repo
  alias Dawarich.Test.{RailsUser, StatsSeeds}

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    user =
      RailsUser.insert!(%{
        id: 5393,
        email: "a5s3-insights@dawarich.test",
        settings: %{"timezone" => "Europe/Berlin"}
      })

    for {id, year, month, distance, daily} <- [
          {53_941, 2024, 3, 38_400, [[5, 10_000], [6, 5_400], [7, 14_000], [20, 9_000]]},
          {53_942, 2024, 4, 12_000, [[10, 12_000]]},
          {53_943, 2023, 7, 20_000, [[14, 20_000]]}
        ] do
      StatsSeeds.stat!(user.id, %{
        id: id,
        year: year,
        month: month,
        distance: distance,
        daily_distance: daily,
        toponyms: [StatsSeeds.toponym("Germany", ["Berlin"])],
        created_at: ~N[2026-09-20 10:00:00],
        updated_at: ~N[2026-09-20 10:00:00]
      })
    end

    %{user: user}
  end

  defp live_as(user, path),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  test "the newest year opens with its totals, the heatmap island and both lazy Rails frames", %{
    user: user
  } do
    {:ok, view, _html} = live_as(user, "/insights")

    assert has_element?(view, "label.btn", "2024 Overview")

    assert has_element?(
             view,
             "#activity-heatmap-card[phx-hook='RailsStimulus'][phx-update='ignore'][data-controller='activity-heatmap']"
           )

    assert has_element?(view, "#activity-heatmap-card [data-date='2024-03-07'].bg-success")

    assert has_element?(
             view,
             "turbo-frame#residency-content[src='/map/residency?year=2024'][loading='lazy'][phx-update='ignore']"
           )

    assert has_element?(
             view,
             "turbo-frame#insights_details[src='/insights/details?year=2024'][loading='lazy'][phx-update='ignore']"
           )
  end

  test "the month parameter reaches the details frame in Rails' query order", %{user: user} do
    {:ok, view, _html} = live_as(user, "/insights?year=2024&month=3")

    assert has_element?(
             view,
             "turbo-frame#insights_details[src='/insights/details?month=3&year=2024']"
           )
  end

  test "All Time has no heatmap, no streak and no residency frame", %{user: user} do
    {:ok, view, _html} = live_as(user, "/insights?year=all")
    refute has_element?(view, "#activity-heatmap-card")
    refute has_element?(view, "turbo-frame#residency-content")
    assert has_element?(view, "turbo-frame#insights_details[src='/insights/details?year=all']")
  end

  test "a year without stats says so with Rails' wording", %{user: user} do
    {:ok, _view, html} = live_as(user, "/insights?year=2020")

    assert html =~
             "No stats data available for 2020. Stats are calculated from your tracked points."

    assert html =~ "0 active days"
  end

  test "a restricted user's locked year shows Pro cards and no frame source", %{user: user} do
    user = Dawarich.Accounts.get(user.id)
    System.put_env("JWT_SECRET_KEY", "phoenix-a5-jwt-fixture-secret-not-for-production")
    on_exit(fn -> System.delete_env("JWT_SECRET_KEY") end)
    context = %{locale: "en", now: ~U[2026-09-26 12:00:00Z], self_hosted: false}
    Repo.query!("UPDATE users SET plan = 0 WHERE id = $1", [user.id])
    user = Dawarich.Accounts.get(user.id)
    page = DawarichWeb.InsightsLive.Index.page(user, %{"year" => "2024"}, context)

    refute Map.has_key?(page, :badge) or Map.has_key?(page, :alert_href) or
             Map.has_key?(page, :upgrades)

    html =
      render_component(
        &DawarichWeb.InsightsLive.Index.render/1,
        Map.merge(
          context,
          Map.merge(page, %{
            current_user: user,
            rails_csrf_token: "CSRF",
            base_url: "http://www.example.com"
          })
        )
      )

    assert page.year_locked
    assert html =~ "utm_content=insights_total_distance"
    assert html =~ "utm_medium=insights"
    assert html =~ ~s(<turbo-frame id="insights_details">)
    refute html =~ "/insights/details?"
  end

  test "a year beyond the calendar is not found", %{user: user} do
    assert_raise DawarichWeb.NotFoundError, fn -> live_as(user, "/insights?year=99999") end
  end
end
