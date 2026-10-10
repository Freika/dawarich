defmodule DawarichWeb.HomeGateTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.HomeGate

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok = Dawarich.State.put_registration_enabled(Repo, true)
    original = Application.get_env(:dawarich, :rails_routes, [])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, original) end)

    RailsUser.insert!(%{
      id: 10001,
      email: "a10-home@example.invalid",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    :ok
  end

  test "home gate owns supported authenticated and anonymous root and respects home rollback" do
    Application.put_env(:dawarich, :rails_routes, [])
    assert true == HomeGate.owned?(prepared("/?return_to=elsewhere"), %{})
    assert true == HomeGate.owned?(Plug.Test.conn(:get, "/"), %{})

    for query <-
          ~w(client=mobile referral=x _method=post format=json return_to[]=x return_to=x&return_to=y) do
      assert false == HomeGate.owned?(prepared("/?" <> query), %{})
    end

    for {key, value} <- [
          {"turbo-frame", "frame"},
          {"accept", "application/json"},
          {"x-http-method-override", "post"}
        ] do
      assert false == HomeGate.owned?(prepared("/") |> put_req_header(key, value), %{})
    end

    assert false ==
             HomeGate.owned?(
               prepared("/")
               |> prepend_req_headers([{"authorization", "A"}, {"authorization", "B"}]),
               %{}
             )

    session = Map.put(RailsUser.session(10001), "client", "mobile")

    marked =
      Plug.Test.conn(:get, "/")
      |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))

    assert false == HomeGate.owned?(marked, %{})
    Application.put_env(:dawarich, :rails_routes, ["home"])
    assert false == HomeGate.owned?(prepared("/"), %{})
    Application.put_env(:dawarich, :rails_routes, ["insights"])
    assert true == HomeGate.owned?(prepared("/"), %{})
  end

  defp prepared(url) do
    Plug.Test.conn(:get, url)
    |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(RailsUser.session(10001)))
  end
end
