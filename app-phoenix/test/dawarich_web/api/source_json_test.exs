defmodule DawarichWeb.Api.SourceJSONTest do
  use ExUnit.Case, async: true

  test "native JSON accepts Rails block comments and preserves quoted markers" do
    raw = ~s({"locations":[] /* c */,"note":"a/*b*/c\\\"//d"})

    conn =
      Plug.Test.conn(:post, "/api/v1/points", raw)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> DawarichWeb.Api.Transport.parse()

    assert conn.assigns.api_params == %{"locations" => [], "note" => ~s(a/*b*/c\"//d)}

    for raw <- [~s({"locations":[] /* c }), ~s({"a":1 /* c */ "b":2})] do
      conn =
        Plug.Test.conn(:post, "/api/v1/points", raw)
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> DawarichWeb.Api.Transport.parse()

      assert conn.status == 400
    end
  end
end
