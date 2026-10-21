defmodule DawarichWeb.NativeRequestTest do
  use ExUnit.Case, async: true

  test "an owned HEAD request keeps its original method for the rate limiter" do
    conn =
      Plug.Test.conn(:head, "http://www.example.com/stats") |> DawarichWeb.NativeRequest.call([])

    assert conn.private.dawarich_method == "HEAD"
    assert conn.method == "GET"
  end

  test "retired trip sharing cannot replay through a lifecycle route key" do
    response =
      Plug.Test.conn(:post, "/trips/42/share_link?source=retired", "synthetic=unchanged")
      |> DawarichWeb.NativeRequest.call([])

    assert response.status == 404
  end
end
