defmodule DawarichWeb.NativeTripEffectsTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "native-trip-effects-#{id}@dawarich.test",
      settings: %{"timezone" => "UTC"}
    })

    TripsSeeds.trip!(%{
      id: id * 10,
      user_id: id,
      started_at: ~N[2026-06-01 12:00:00],
      ended_at: ~N[2026-06-03 12:00:00]
    })

    %{id: id}
  end

  test "native trip deletion removes its admitted resource and navigates to the trip list", %{
    id: id
  } do
    {:ok, view, _} = open(id)
    assert has_element?(view, "[phx-click='trip:delete'][data-confirm]")
    view |> element("[phx-click='trip:delete']") |> render_click()
    assert_redirect(view, "/trips")
    assert Repo.query!("SELECT id FROM trips WHERE id=$1", [id * 10], log: false).rows == []
  end

  test "native trip recalculation queues once and preserves cooldown feedback", %{id: id} do
    Dawarich.Jobs.Ownership.put!(Repo, "command:trips.calculate", :oban)
    {:ok, view, _} = open(id)
    assert has_element?(view, "[phx-click='trip:recalculate'][data-confirm]")
    view |> element("[phx-click='trip:recalculate']") |> render_click()
    assert has_element?(view, "#flash-messages", "Recalculating")
    assert has_element?(view, "[phx-click='trip:recalculate'][disabled]")

    assert [[%{"trip_id" => trip_id, "distance_unit" => "km"}]] =
             Repo.query!(
               "SELECT payload FROM job_outbox WHERE command_type='trips.calculate' AND aggregate_id=$1",
               [id * 10],
               log: false
             ).rows

    assert trip_id == id * 10
    render_click(view, "trip:recalculate", %{})
    assert has_element?(view, "#flash-messages", "Already recalculating")

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM job_outbox WHERE command_type='trips.calculate' AND aggregate_id=$1",
               [id * 10],
               log: false
             ).rows
  end

  test "native trip exports retain both formats and refuse an invalid export locally", %{id: id} do
    Dawarich.Jobs.Ownership.put!(Repo, "command:exports.points", :oban)

    for {format, expected} <- [{"gpx", 1}, {"json", 0}] do
      {:ok, view, _} = open(id)
      assert has_element?(view, "[phx-click='trip:export'][phx-value-format=#{format}]")
      view |> element("[phx-click='trip:export'][phx-value-format=#{format}]") |> render_click()
      assert_redirect(view, "/exports")

      assert [[^expected, ~N[2026-06-01 12:00:00.000000], ~N[2026-06-03 12:00:00.000000]]] =
               Repo.query!(
                 "SELECT file_format,start_at,end_at FROM exports WHERE user_id=$1 ORDER BY id DESC LIMIT 1",
                 [id],
                 log: false
               ).rows
    end

    {:ok, view, _} = open(id)
    render_click(view, "trip:export", %{"format" => "bogus"})
    assert has_element?(view, "#flash-messages", "Unsupported")
    assert has_element?(view, "#trip-shell")

    assert [[2]] =
             Repo.query!("SELECT count(*) FROM exports WHERE user_id=$1", [id], log: false).rows

    Repo.query!("DELETE FROM trips WHERE id=$1", [id * 10], log: false)
    render_click(view, "trip:export", %{"format" => "gpx"})
    assert_push_event(view, "map:clear", %{})
    refute has_element?(view, "#trip-shell")

    assert [[2]] =
             Repo.query!("SELECT count(*) FROM exports WHERE user_id=$1", [id], log: false).rows
  end

  test "native trip recalculation refusal leaves its resource and job graph unchanged", %{id: id} do
    Dawarich.Jobs.Ownership.put!(Repo, "command:trips.calculate", :sidekiq)
    {:ok, view, _} = open(id)
    view |> element("[phx-click='trip:recalculate']") |> render_click()
    assert has_element?(view, "#flash-messages", "Recalculation failed")
    assert has_element?(view, "#trip-shell")

    assert [[nil]] =
             Repo.query!("SELECT last_recalculated_at FROM trips WHERE id=$1", [id * 10],
               log: false
             ).rows

    assert Repo.query!(
             "SELECT event_id FROM job_outbox WHERE command_type='trips.calculate' AND aggregate_id=$1",
             [id * 10], log: false).rows == []
  end

  defp open(id, resource \\ nil) do
    path = "/trips/#{resource || id * 10}"

    RailsUser.signed_in(id)
    |> RailsUser.connecting_as(id)
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
    |> Map.merge(%{
      request_path: path,
      path_info: ["trips", to_string(resource || id * 10)],
      query_string: ""
    })
    |> Plug.Conn.fetch_query_params()
    |> Dawarich.Test.NativeM6IntegrationRouter.call([])
    |> live()
  end
end
