defmodule DawarichWeb.NativeTripMapTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  alias Dawarich.{Accounts, Maps, Repo}
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint
  @now ~U[2026-09-29 12:00:00Z]
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    TripsSeeds.user!(8841, %{"timezone" => "UTC"})
    TripsSeeds.user!(8899, %{"timezone" => "UTC"})

    TripsSeeds.trip!(%{
      id: 884_101,
      user_id: 8841,
      path: [[12.37, 51.338], [12.381, 51.341]],
      started_at: ~N[2026-06-01 22:00:00],
      ended_at: ~N[2026-06-03 01:00:00]
    })

    %{user: Accounts.get(8841)}
  end

  test "native trip map admits only the owned trip and excludes bulk state", ctx do
    scope = Maps.principal(ctx.user, "en")
    assert {:ok, metadata} = Dawarich.Maps.Dependencies.Trip.config(scope, 884_101, now: @now)
    assert metadata["tripId"] == 884_101
    assert metadata["range"]["startAt"] == "2026-06-01T22:00:00Z"
    refute Map.has_key?(metadata, "path")
    refute Map.has_key?(metadata, "api_key")

    assert {:error, :not_found} =
             Dawarich.Maps.Dependencies.Trip.config(
               Maps.principal(Accounts.get(8899), "en"),
               884_101, now: @now)

    conn =
      RailsUser.signed_in(ctx.user.id)
      |> Plug.Conn.assign(:now, @now)
      |> get("/native/map/data/trips/884101")

    assert conn.status == 200
    data = json_response(conn, 200)
    assert data["path"] == [[12.37, 51.338], [12.381, 51.341]]
    assert data["deviceWindows"] == []
    refute conn.resp_body =~ "api_key"
    assert (RailsUser.signed_in(8899) |> get("/native/map/data/trips/884101")).status == 404
  end

  test "trip map adapter refuses the original revoked session", ctx do
    scope = Maps.principal(ctx.user, "en")

    Repo.query!("UPDATE users SET encrypted_password = 'synthetic-revoked' WHERE id = $1", [
      ctx.user.id
    ])

    assert {:error, :stale_session} =
             Dawarich.Maps.Dependencies.Trip.config(scope, 884_101, now: @now)
  end
end
