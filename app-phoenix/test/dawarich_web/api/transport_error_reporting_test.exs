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

  test "native transport reports unexpected error exactly once without request secrets" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    previous = Map.new(~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL), &{&1, System.get_env(&1)})
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true", "FORCE_SSL" => "false"})

    on_exit(fn ->
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    body = Jason.encode!(%{"settings" => %{"note" => "private-body"}})

    conn =
      conn(:patch, "/api/v1/settings/mobile?otp=654321&lat=52.12345", body)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer synthetic-credential")
      |> assign(:api_now, "victim@example.invalid synthetic-credential 13.54321")
      |> DawarichWeb.Endpoint.call(DawarichWeb.Endpoint.init([]))

    assert conn.status == 500
    assert Jason.decode!(conn.resp_body) == %{"status" => 500, "error" => "Internal Server Error"}
    {_item, payload} = envelope()
    assert hd(payload["exception"])["stacktrace"]["frames"] != []
    assert payload["tags"]["surface"] == "web"
    assert_private(payload)
    refute_receive {:envelope, _, _}
  end
end
