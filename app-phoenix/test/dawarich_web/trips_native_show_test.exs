defmodule DawarichWeb.TripsNativeShowTest do
  use Dawarich.DataCase, async: false

  import Phoenix.LiveViewTest

  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.{NativeAdminUI, TripsNativeUI, TripsSeeds}
  alias DawarichWeb.NativeTripsLive.Show

  @path [[12.5, 51.25], [12.373468123456789, 51.34]]

  setup do
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Dawarich.Repo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, previous) end)
    Ownership.put!(Repo, "command:trips.calculate", :oban)
    TripsSeeds.country!("Germany", "DE", "DEU")
    TripsSeeds.user!(9_961)
    TripsSeeds.user!(9_962)
    :ok
  end

  defp trip!(id, attrs \\ %{}) do
    TripsSeeds.trip!(
      Map.merge(
        %{
          id: id,
          user_id: 9_961,
          path: @path,
          distance: 12_345,
          started_at: ~N[2026-05-09 06:00:00],
          ended_at: ~N[2026-05-12 20:00:00]
        },
        attrs
      )
    )
  end

  defp day_keys(view),
    do:
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-day-key]")
      |> LazyHTML.attribute("data-day-key")

  test "trip initial and connected renders request one calculation for an input revision" do
    id = trip!(996_101, %{distance: nil, path: nil})

    {_, queries} =
      NativeAdminUI.queries(fn ->
        {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
        render_async(view)
        render_patch(view, "/trips/#{id}?from=2026-05-10")
        render_async(view)
      end)

    assert Enum.count(queries, &(&1 =~ "INSERT INTO public.job_outbox")) == 1
    assert rows("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]) == [[1]]
  end

  test "late day data and old timeout cannot replace the selected trip" do
    first = trip!(996_201)

    second =
      trip!(996_202, %{started_at: ~N[2026-07-01 06:00:00], ended_at: ~N[2026-07-02 20:00:00]})

    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{first}")
    render_async(view)
    assert hd(day_keys(view)) == "2026-05-09"

    render_patch(view, "/trips/#{second}")
    render_async(view)
    assert day_keys(view) == ~w(2026-07-01 2026-07-02)

    send(view.pid, {:data_read_timeout, {:days, 1, make_ref(), {first, nil}}})
    refute has_element?(view, "[data-days-status='failed']")

    socket = :sys.get_state(view.pid).socket
    late = %{days: [%{date: ~D[2026-05-09], stats: nil, note: nil}], next: nil}

    assert {:noreply, kept} =
             Show.handle_async({:days, 1, make_ref(), {first, nil}}, {:ok, {:ok, late}}, socket)

    assert Enum.map(kept.assigns.days, & &1.date) == [~D[2026-07-01], ~D[2026-07-02]]
    assert day_keys(view) == ~w(2026-07-01 2026-07-02)
  end

  test "revoked or deleted trip clears data before update delivery" do
    id = trip!(996_301)
    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
    render_async(view)

    rows("UPDATE trips SET name='Renamed by worker' WHERE id=$1", [id])
    Dawarich.Trips.Events.broadcast(id)
    assert render(view) =~ "Renamed by worker"

    rows("DELETE FROM trips WHERE id=$1", [id])
    send(view.pid, {:domain_changed, id, :trip})
    assert_redirect(view, "/trips")

    other = trip!(996_302)
    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{other}")
    rows("UPDATE users SET encrypted_password=$1 WHERE id=9961", [String.duplicate("q", 60)])
    send(view.pid, {:domain_changed, other, :trip})
    assert_redirect(view, "/users/sign_in")
  end

  test "a notification sign-out refuses the trip page immediately" do
    id = trip!(996_303)
    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
    render_async(view)

    send(view.pid, :notification_signed_out)
    assert_redirect(view, "/users/sign_in")
  end

  test "detail shows source values without paths keys or provider settings" do
    rows("UPDATE users SET settings=$1 WHERE id=9961", [
      %{
        "timezone" => "Europe/Berlin",
        "immich_url" => "https://p.invalid",
        "immich_api_key" => "provider-secret"
      }
    ])

    id = trip!(996_401)
    TripsSeeds.rich_text!(id, ~S|<div>Notes <a href="javascript:alert(1)">x</a></div>|)

    TripsSeeds.note!(%{
      id: 996_491,
      trip_id: id,
      user_id: 9_961,
      body: "Lunch by the lake",
      noted_at: ~N[2026-05-10 12:00:00]
    })

    {:ok, view, html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
    assert html =~ "trip 996401"
    assert html =~ "3 days, 14 hours"
    assert html =~ "12 km"
    assert html =~ "1 country"
    assert html =~ "Notes"
    refute html =~ "javascript:"

    render_async(view)
    assert day_keys(view) == ~w(2026-05-09 2026-05-10 2026-05-11 2026-05-12)
    assert render(view) =~ "Lunch by the lake"

    state = inspect(:sys.get_state(view.pid).socket.assigns, limit: :infinity)

    for secret <- ["provider-secret", "a8-k-9961", "12.37346", "p.invalid"],
        do: refute(state =~ secret)

    refute render(view) =~ "a8-k-9961"
  end

  test "toolbar events recalculate, export and delete through scoped commands" do
    id = trip!(996_501)
    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")

    assert render_click(view, "recalculate") =~ "Recalculating"
    assert rows("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]) == [[1]]

    render_click(view, "export", %{"format" => "gpx"})
    assert %{"notice" => exported} = assert_redirect(view, "/exports")
    assert exported =~ "export"
    assert rows("SELECT count(*) FROM exports WHERE user_id=9961") == [[1]]

    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
    render_click(view, "delete")
    flash = assert_redirect(view, "/trips")
    assert flash["notice"] =~ "destroyed"
    assert rows("SELECT count(*) FROM trips WHERE id=$1", [id]) == [[0]]
  end

  test "foreign trips are not found and a failed day read can retry" do
    foreign = trip!(996_601, %{user_id: 9_962})
    assert TripsNativeUI.not_found?(9_961, "/trips/#{foreign}")

    id = trip!(996_602)
    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
    render_async(view)
    socket = :sys.get_state(view.pid).socket

    {run, pending} = DawarichWeb.TripsNative.Access.register(socket, :days, {id, nil})
    assert {:noreply, failed} = Show.handle_async(run, {:exit, :boom}, pending)
    assert failed.assigns.days_status == :failed

    render_click(view, "retry_days")
    render_async(view)
    assert length(day_keys(view)) == 4
    refute has_element?(view, "[data-days-status='failed']")
  end
end
