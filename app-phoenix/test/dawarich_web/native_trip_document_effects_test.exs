defmodule DawarichWeb.NativeTripDocumentEffectsTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "trip-document-#{id}@dawarich.test",
      settings: %{"timezone" => "UTC"}
    })

    TripsSeeds.trip!(%{
      id: id * 10,
      user_id: id,
      started_at: ~N[2026-06-01 12:00:00],
      ended_at: ~N[2026-06-03 12:00:00]
    })

    TripsSeeds.point!(%{
      id: id * 100,
      user_id: id,
      timestamp: DateTime.to_unix(~U[2026-06-01 13:00:00Z]),
      at: [13, 52]
    })

    owner = self()
    handler = {__MODULE__, owner}

    :ok =
      :telemetry.attach(
        handler,
        [:dawarich, :repo, :query],
        fn _, _, meta, _ ->
          if String.contains?(meta.query, "INSERT INTO public.job_outbox") &&
               match?([%{"trip_id" => _} | _], meta.params) &&
               hd(meta.params)["trip_id"] == id * 10 do
            send(owner, {:trip_document_attempt, id * 10})
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    %{id: id, path: "/trips/#{id * 10}"}
  end

  test "native trip document schedules missing calculations once and connected callbacks never duplicate",
       %{id: id, path: path} do
    Dawarich.Jobs.Ownership.put!(Repo, "command:trips.calculate", :oban)
    conn = RailsUser.signed_in(id) |> RailsUser.connecting_as(id) |> get(path)
    assert count(id) == 1
    trip = id * 10
    assert_receive {:trip_document_attempt, ^trip}, 1000
    {:ok, view, _} = live(conn)
    assert has_element?(view, "[data-trip-map-state=calculating]")
    render_hook(view, "map:ready", %{})
    render_patch(view, path <> "?refresh=1")
    assert count(id) == 1
    refute_receive {:trip_document_attempt, ^trip}, 0

    assert Repo.query!("SELECT count(*) FROM phoenix.rails_commands", [], log: false).rows == [
             [0]
           ]
  end

  test "native trip document refuses a source-owned producer locally without handback or writes",
       %{id: id, path: path} do
    Dawarich.Jobs.Ownership.put!(Repo, "command:trips.calculate", :sidekiq)
    conn = RailsUser.signed_in(id) |> get(path)
    assert conn.status == 200
    assert count(id) == 0
    assert String.contains?(conn.resp_body, "Recalculation failed")
    assert String.contains?(conn.resp_body, "trip-shell")
    refute String.contains?(conn.resp_body, "data-controller")
    assert Plug.Conn.get_resp_header(conn, "location") == []

    assert Repo.query!("SELECT count(*) FROM phoenix.rails_commands", [], log: false).rows == [
             [0]
           ]
  end

  test "native trip document refuses malformed identities before reading or calculation", %{
    id: id,
    path: path
  } do
    Dawarich.Jobs.Ownership.put!(Repo, "command:trips.calculate", :oban)

    for bad <- [path <> "suffix", "/trips/" <> String.duplicate("9", 100), "/trips/-1"] do
      conn = RailsUser.signed_in(id) |> get(bad)
      assert conn.status == 200
      refute String.contains?(conn.resp_body, "trip-shell")
      assert String.contains?(conn.resp_body, "invalid")
    end

    assert count(id) == 0
  end

  defp count(id),
    do:
      Repo.query!(
        "SELECT count(*) FROM job_outbox WHERE command_type='trips.calculate' AND aggregate_id=$1",
        [id * 10],
        log: false
      ).rows
      |> hd()
      |> hd()
end
