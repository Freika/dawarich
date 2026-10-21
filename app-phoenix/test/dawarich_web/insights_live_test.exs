defmodule DawarichWeb.InsightsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.Repo
  alias Dawarich.Test.{RailsUser, StatsSeeds}

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Dawarich.DataCase.setup_sandbox(%{async: false})

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
    do: connected(user, path)

  defp connected(user, path) do
    {:ok, view, html} =
      live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

    render_async(view, 5000)
    {:ok, view, html}
  end

  test "the newest native year opens with source totals heatmap and independent ready reads", %{
    user: user
  } do
    {:ok, view, _} = live_as(user, "/insights")
    assert :sys.get_state(view.pid).socket.assigns.data.year == 2024
    assert :sys.get_state(view.pid).socket.assigns.data.totals.distance == 50
    assert has_element?(view, "[data-testid=year-calendar-streaks]", "5 active days")
    assert has_element?(view, "[data-date='2024-03-07'][aria-label*='14 km']")
    assert has_element?(view, "#insights-residency-ready")
    refute render(view) =~ "turbo-frame"
  end

  test "the native month parameter reaches the ready details projection", %{user: user} do
    {:ok, view, _} = live_as(user, "/insights?year=2024&month=3")
    assert :sys.get_state(view.pid).socket.assigns.data.selected_month == 3
    assert :sys.get_state(view.pid).socket.assigns.details.value.selected_month == 3
  end

  test "native All Time keeps source totals without heatmap streak or residency work", %{
    user: user
  } do
    {:ok, view, _} = live_as(user, "/insights?year=all")
    refute has_element?(view, "#activity-heatmap-card")
    refute has_element?(view, "#insights-residency-ready")
    assert :sys.get_state(view.pid).socket.assigns.details.value.totals.distance == 70
    assert :sys.get_state(view.pid).socket.assigns.residency == nil
  end

  test "a year without stats says so with Rails' wording", %{user: user} do
    {:ok, view, html} = live_as(user, "/insights?year=2020")

    assert html =~
             "No stats data available for 2020. Stats are calculated from your tracked points."

    assert has_element?(view, "[data-testid=year-calendar-streaks]", "0 active days")
  end

  test "native locked year retains Pro access and generates an upgrade only on action", %{
    user: user
  } do
    old = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")
    System.put_env("JWT_SECRET_KEY", "synthetic-insights-upgrade")

    on_exit(fn ->
      if old, do: System.put_env("SELF_HOSTED", old), else: System.delete_env("SELF_HOSTED")
      System.delete_env("JWT_SECRET_KEY")
    end)

    Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [user.id])
    {:ok, view, _} = live_as(user, "/insights?year=2024")
    assert has_element?(view, "#insights-locked[role=status]")
    assert :sys.get_state(view.pid).socket.private.data_async.runs == %{}
    refute :erlang.term_to_binary(:sys.get_state(view.pid).socket.assigns) =~ "token="
    render_click(view, "upgrade", %{})
    {url, _} = assert_redirect(view)
    assert URI.decode_query(URI.parse(url).query)["utm_content"] == "insights"
  end

  test "a native year beyond the calendar refuses in place without source data", %{user: user} do
    {:ok, view, _} = live_as(user, "/insights?year=99999")
    assert :sys.get_state(view.pid).socket.assigns.data == nil
    assert render(view) =~ "alert"
  end
end
