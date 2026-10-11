defmodule DawarichWeb.Api.ClientSessionTest do
  use ExUnit.Case, async: false
  import Plug.Conn

  setup do
    previous = Application.get_env(:dawarich, :rails_secret)
    Application.put_env(:dawarich, :rails_secret, "synthetic-cookie-secret")
    on_exit(fn -> Application.put_env(:dawarich, :rails_secret, previous) end)
  end

  test "API clears an invalid remember cookie with the Rails expiry attributes" do
    conn =
      Plug.Test.conn(:post, "/api/v1/points")
      |> put_req_header("cookie", "remember_user_token=invalid")
      |> assign(:api_params, %{})
      |> DawarichWeb.Api.ClientSession.call()

    assert %{http_only: false, max_age: 0, same_site: "Lax", path: "/"} =
             conn.resp_cookies["remember_user_token"]

    assert conn.assigns.current_user == nil
  end
end
