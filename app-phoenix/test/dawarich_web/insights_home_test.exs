defmodule DawarichWeb.InsightsHomeTest do
  use ExUnit.Case, async: false
  import Plug.Conn

  @tag a10_boundary: :home
  test "root full boundary replaces insights ownership with home" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)

    Dawarich.Test.RailsUser.insert!(%{
      id: 10001,
      email: "a10-home@example.invalid",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    route = Phoenix.Router.route_info(DawarichWeb.Router, "GET", "/", "www.example.com")
    assert route.pipe_through == [:public_home]
    assert route.rails_gate == {DawarichWeb.HomeGate, :owned?}
    original = Application.get_env(:dawarich, :rails_routes, [])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, original) end)
    owner = self()
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:dawarich, :repo, :query],
        fn _, _, metadata, owner ->
          send(owner, {:home_query, metadata.query})
        end,
        owner
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    query = "?return_to=https%3A%2F%2Fevil.invalid"

    for rollback <- [[], ["insights"]] do
      Application.put_env(:dawarich, :rails_routes, rollback)

      conn =
        Phoenix.ConnTest.dispatch(
          Dawarich.Test.RailsUser.signed_in(10001),
          DawarichWeb.Endpoint,
          :get,
          "/" <> query,
          nil
        )

      state = Jason.decode!(File.read!("test/fixtures/trial_home/home_signed_in.json"))
      assert conn.status == state["status"]
      assert conn.resp_body == ""
      assert get_resp_header(conn, "location") == [state["headers"]["location"]]
      assert get_resp_header(conn, "cache-control") == [state["headers"]["cache-control"]]
    end

    queries = collect_queries([])

    assert Enum.all?(
             queries,
             &(not Regex.match?(~r/\b(?:FROM|JOIN)\s+(?:"?public"?\.)?"?points"?\b/i, &1))
           )

    Application.put_env(:dawarich, :rails_routes, ["home"])

    assert false ==
             DawarichWeb.Strangler.gate_open?(
               route,
               Plug.Test.conn(:get, "/")
               |> Plug.Test.put_req_cookie(
                 "_dawarich_session",
                 Dawarich.Test.RailsUser.cookie(Dawarich.Test.RailsUser.session(10001))
               )
             )
  end

  defp collect_queries(acc) do
    receive do
      {:home_query, query} -> collect_queries([query | acc])
    after
      0 -> acc
    end
  end

  test "authenticated preferred-map redirect preserves actual Source absolute URL, empty body and cache policy" do
    conn =
      Plug.Test.conn(
        :get,
        "http://www.example.com/?return_to=https%3A%2F%2Fevil.invalid&year=2024"
      )
      |> DawarichWeb.RailsHeaders.call([])
      |> DawarichWeb.InsightsFrame.call([])
      |> DawarichWeb.InsightsHome.index(%{
        "return_to" => "https://evil.invalid",
        "year" => "2024"
      })

    assert conn.status == 302
    assert conn.resp_body == ""
    assert get_resp_header(conn, "location") == ["http://www.example.com/map/v2"]
    assert get_resp_header(conn, "cache-control") == ["no-cache"]
    assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
  end
end
