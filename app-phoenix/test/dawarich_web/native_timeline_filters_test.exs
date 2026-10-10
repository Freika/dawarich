defmodule DawarichWeb.NativeTimelineFiltersTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Maps}
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  alias DawarichWeb.MapLive.TimelineFilters
  @endpoint DawarichWeb.Endpoint

  defmodule Host do
    use Phoenix.LiveView

    def mount(_params, session, socket) do
      {:ok,
       assign(socket,
         current_scope: Maps.principal(Accounts.get(session["user_id"]), "en"),
         map_url: %{},
         calendar_loader: Agent.get(session["loader"], & &1),
         calendar_timeout: 50
       )}
    end

    def handle_event(event, payload, socket),
      do: TimelineFilters.handle_event(event, payload, socket)

    def handle_async(name, result, socket), do: TimelineFilters.handle_async(name, result, socket)

    def render(assigns) do
      ~H"""
      <DawarichWeb.NativeTimelineCalendar.calendar calendar={assigns[:calendar]} locale="en" />
      """
    end
  end

  setup do
    id = System.unique_integer([:positive])
    FrameSeeds.user!(id, %{"timezone" => "Europe/Berlin"})
    %{id: id}
  end

  test "calendar navigation keeps profile day and filters in URL", %{id: id} do
    view =
      open(
        id,
        "/map/v2?start_at=2026-03-29T00:00&end_at=2026-03-29T23:59&import_id=7&panel=timeline&date=2026-03-29"
      )

    render_hook(view, "calendar:month", %{"month" => "2026-03"})
    html = render_async(view, 5_000)
    assert html =~ ~s(data-testid="calendar-title")
    assert html =~ "March 2026"

    view |> element("button[data-day='2026-03-30']") |> render_click()
    url = state(view)["url"]
    assert url["date"] == "2026-03-30"
    assert url["start_at"] == "2026-03-30T00:00"
    assert url["end_at"] == "2026-03-30T23:59"
    assert url["import_id"] == "7"
    assert url["panel"] == "timeline"

    view |> element("#native-calendar-prev") |> render_click()
    assert render_async(view, 5_000) =~ "February 2026"
    assert state(view)["url"]["date"] == "2026-03-30"
  end

  test "residency latest year and tie order survive native render", %{id: id} do
    FrameSeeds.stat!(id, 2024, 5)
    FrameSeeds.stat!(id, 2025, 5)
    base = System.unique_integer([:positive]) * 10

    for {country, day, n} <- [
          {"Narnia", 1, 0},
          {"Atlantis", 2, 1},
          {"Germany", 3, 2},
          {"Germany", 4, 3}
        ],
        do:
          FrameSeeds.point!(
            id,
            base + n,
            DateTime.to_unix(DateTime.new!(Date.new!(2025, 5, day), ~T[12:00:00])),
            %{country_name: country}
          )

    view = open(id, "/map/v2")
    render_hook(view, "residency:year", %{})
    html = render(view)
    assert html =~ ~s(data-residency-year="2025")

    {:ok, data} = DawarichWeb.ResidencyFrame.data(Accounts.get(id), nil, DateTime.utc_now())
    [_, list] = String.split(html, ~s(data-testid="residency-country-list"), parts: 2)
    names = Enum.sort_by(~w(Germany Atlantis Narnia), &(:binary.match(list, &1) |> elem(0)))
    assert names == Enum.map(data.countries, & &1.name)
    assert hd(names) == "Germany"
    assert html =~ "residency-country-card"

    rows("UPDATE users SET encrypted_password=$1 WHERE id=$2", [
      String.duplicate("rotated", 10),
      id
    ])

    render_hook(view, "residency:year", %{"year" => "2025"})
    assert_redirect(view, "/users/sign_in")
  end

  test "calendar response timeout belongs only to that run", %{id: id} do
    calls = :counters.new(1, [])

    loader = fn _scope, month ->
      :counters.add(calls, 1, 1)
      if month == "2026-01", do: receive(do: (:never -> :ok))
      {:ok, %{month: month, weeks: []}}
    end

    agent = start_supervised!({Agent, fn -> loader end})

    {:ok, view, _} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host,
        session: %{"user_id" => id, "loader" => agent}
      )

    render_hook(view, "calendar:month", %{"month" => "2026-01"})
    render_hook(view, "calendar:month", %{"month" => "2026-02"})
    html = render_async(view, 2_000)
    refute html =~ ~s(role="alert")
    assert html =~ "February 2026"
    assert :counters.get(calls, 1) >= 1
  end

  defp state(view),
    do:
      view
      |> element("#state")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.text()
      |> Jason.decode!()

  defp open(id, path) do
    {:ok, view, _} =
      RailsUser.signed_in(id)
      |> RailsUser.connecting_as(id)
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
      |> Map.merge(%{
        request_path: "/map/v2",
        path_info: ["map", "v2"],
        query_string: URI.parse(path).query || ""
      })
      |> Plug.Conn.fetch_query_params()
      |> Dawarich.Test.NativeMapShellRouter.call([])
      |> live()

    view
  end
end
