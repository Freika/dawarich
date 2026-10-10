defmodule DawarichWeb.Api.TransportErrorReportingTest do
  use Dawarich.ErrorReportingCase, async: false
  import Plug.Test
  import Plug.Conn

  test "an exception inside a native API request is reported once and still answers 500" do
    conn =
      conn(:get, "/api/v1/ready?otp=654321&lat=52.12345")
      |> put_req_header("accept", "application/json")
      |> assign(:readiness_opts, :misconfigured)
      |> put_private(:dawarich_native_api, true)
      |> DawarichWeb.Api.Transport.call(:router)

    assert conn.status == 500
    assert Jason.decode!(conn.resp_body) == %{"status" => 500, "error" => "Internal Server Error"}
    {_item, payload} = envelope()
    assert hd(payload["exception"])["stacktrace"]["frames"] != []
    assert payload["tags"]["surface"] == "web"
    assert_private(payload)
    refute_receive {:envelope, _, _}
  end
end
