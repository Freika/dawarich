defmodule DawarichWeb.AuthGateTest do
  use ExUnit.Case, async: false

  alias DawarichWeb.AuthGate

  @credentials [
    {:get, "/users/sign_in"},
    {:post, "/users/sign_in"},
    {:post, "/users/sign_out"},
    {:delete, "/users/sign_out"}
  ]
  @recovery [
    {:get, "/users/password/new"},
    {:get, "/users/password/edit"},
    {:post, "/users/password"},
    {:put, "/users/password"},
    {:get, "/users/unlock/new"},
    {:get, "/users/unlock"},
    {:post, "/users/unlock"}
  ]
  @elsewhere [
    {:head, "/users/sign_in"},
    {:get, "/users/sign_in/"},
    {:get, "/users/edit"},
    {:post, "/users"},
    {:get, "/users/sign_up"}
  ]

  setup do
    Application.delete_env(:dawarich, :phoenix_auth)
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      Application.delete_env(:dawarich, :phoenix_auth)

      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)
  end

  defp request({method, path}) do
    body = "authenticity_token=x&user%5Bemail%5D=a%40dawarich.test"

    Plug.Test.conn(method, path, body)
    |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
    |> Plug.Conn.put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> Plug.Conn.put_req_header("cookie", "_dawarich_session=opaque")
  end

  defp untouched(routes) do
    for route <- routes do
      conn = request(route)
      assert AuthGate.call(conn, []) == conn, inspect(route)
    end
  end

  test "with no flow named, every auth request passes through untouched" do
    untouched(@credentials ++ @recovery ++ @elsewhere)
  end

  test "reserved and unknown flow names change nothing" do
    Application.put_env(
      :dawarich,
      :phoenix_auth,
      ~w(registration two_factor remember oauth bogus)
    )

    untouched(@credentials ++ @recovery ++ @elsewhere)
  end

  test "credentials claims only its own four routes" do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    untouched(@recovery ++ @elsewhere)
  end

  test "recovery claims only its own seven routes" do
    Application.put_env(:dawarich, :phoenix_auth, ["recovery"])
    untouched(@credentials ++ @elsewhere)
  end

  test "credentials and recovery on, an instance that is not self-hosted: even their own routes pass untouched" do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials", "recovery"])

    for value <- [nil, "false", "TRUE", ""] do
      if value, do: System.put_env("SELF_HOSTED", value), else: System.delete_env("SELF_HOSTED")
      untouched(@credentials ++ @recovery)
    end
  end
end
