defmodule DawarichWeb.ErrorReportingTest do
  use Dawarich.ErrorReportingCase, async: false
  import Dawarich.Test.RawHTTP

  test "an unhandled Bandit Phoenix request reports one scrubbed exception and keeps its error response" do
    previous = Application.fetch_env!(:dawarich, :public_files)

    Application.put_env(:dawarich, :public_files, %{
      bad_config: "victim@example.invalid synthetic-credential"
    })

    on_exit(fn -> Application.put_env(:dawarich, :public_files, previous) end)
    bandit = start_supervised!({Bandit, plug: DawarichWeb.Endpoint, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, port}} = ThousandIsland.listener_info(bandit)
    socket = connect(port)

    send_raw(
      socket,
      "GET /unhandled?otp=654321&lat=52.12345 HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer synthetic-credential\r\nCookie: private-cookie\r\nConnection: close\r\n\r\n"
    )

    assert {500, headers, body} = read_response(socket)
    assert {"content-type", "text/html; charset=utf-8"} in headers
    assert body == File.read!(Dawarich.RailsRoot.join("public/500.html"))
    :gen_tcp.close(socket)
    {_item, payload} = envelope()
    assert hd(payload["exception"])["type"] == "MatchError"
    assert hd(payload["exception"])["stacktrace"]["frames"] != []
    assert payload["tags"]["surface"] == "web"
    assert_private(payload)
    refute_receive {:envelope, _, _}
  end
end
