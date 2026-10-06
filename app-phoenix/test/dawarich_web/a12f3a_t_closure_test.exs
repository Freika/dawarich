defmodule DawarichWeb.A12f3aTClosureTest do
  use Dawarich.IngestCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  alias Dawarich.Jobs.Ownership
  @endpoint DawarichWeb.Endpoint
  @now ~U[2026-10-03 10:00:00.000000Z]

  setup do
    previous = Application.get_env(:dawarich, :jobs_repo)
    hosted = System.get_env("SELF_HOSTED")
    jwt = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", "synthetic-trip-closure")
    Application.put_env(:dawarich, :jobs_repo, Repo)

    on_exit(fn ->
      if jwt, do: System.put_env("JWT_SECRET_KEY", jwt), else: System.delete_env("JWT_SECRET_KEY")
      Application.put_env(:dawarich, :jobs_repo, previous)
      if hosted, do: System.put_env("SELF_HOSTED", hosted), else: System.delete_env("SELF_HOSTED")
    end)

    user =
      RailsUser.insert!(%{
        id: 9801,
        email: "trip-closure@example.test",
        settings: %{"timezone" => "Europe/Berlin"},
        active_until: ~N[3026-10-03 12:00:00]
      })

    Ownership.put!(Repo, "command:trips.calculate", :oban)
    %{user: Dawarich.Accounts.get(user.id)}
  end

  @tag a12f3a_t01: true
  test "T01: trip index and form navigation tails matches current Rails contract without a native-owner Rails effect",
       %{user: user} do
    TripsSeeds.trip!(%{id: 980_101, user_id: user.id, path: [[12.37, 51.33], [12.38, 51.34]]})

    for mode <- ["true", "false", nil] do
      if mode, do: System.put_env("SELF_HOSTED", mode), else: System.delete_env("SELF_HOSTED")

      for path <- ["/trips", "/trips/new", "/trips/980101/edit"] do
        conn = get(RailsUser.signed_in(user.id), path)
        assert conn.status == 200, "#{mode} #{path}"
        assert conn.resp_body =~ "trip"
        assert get(build_conn(), path).status == 302
      end
    end

    foreign = TripsSeeds.user!(9802)
    TripsSeeds.trip_source!(980_102, foreign.id)
    Repo.query!("UPDATE trips SET trip_source_id=$2 WHERE id=$1", [980_101, 980_102])
    assert Dawarich.TripList.gate(user, 1) == :rails
    assert commands() == []
  end

  @tag a12f3a_t06: true
  test "T06: trip calculation producers and show callback matches current Rails contract without a native-owner Rails effect",
       %{user: user} do
    System.put_env("SELF_HOSTED", "false")
    TripsSeeds.trip!(%{id: 980_601, user_id: user.id, path: nil})
    assert Dawarich.Trips.ShowCalculation.admitted?(Repo, user, 980_601, @now)
    assert {:ok, :queued} = Dawarich.Trips.ShowCalculation.run(Repo, user, 980_601, %{now: @now})

    assert Repo.query!("SELECT payload FROM job_outbox WHERE command_type='trips.calculate'").rows ==
             [[%{"trip_id" => 980_601, "distance_unit" => "km"}]]

    TripsSeeds.trip!(%{
      id: 980_602,
      user_id: user.id,
      path: nil,
      source_identifier: "synthetic",
      started_at: ~N[2026-11-01 10:00:00],
      ended_at: ~N[2026-11-02 10:00:00]
    })

    assert {:ok, :ready} = Dawarich.Trips.ShowCalculation.run(Repo, user, 980_602, %{now: @now})
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[1]]
    assert get(RailsUser.signed_in(user.id), "/trips/980601").status == 200
    assert commands() == []
  end
end
