defmodule DawarichWeb.TripsGateEndpointTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP

  alias Dawarich.Test.{RailsUser, TripsSeeds}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)
    TripsSeeds.user!(8811)
    TripsSeeds.trip!(%{id: 881_101, user_id: 8811, path: [[12.37, 51.338], [12.381, 51.341]]})

    %{
      upstream: upstream,
      cookie: "_dawarich_session=" <> RailsUser.cookie(RailsUser.session(8811))
    }
  end

  defp serve do
    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    port
  end

  defp request(target, cookie),
    do: "GET #{target} HTTP/1.1\r\nHost: a\r\nCookie: #{cookie}\r\n\r\n"

  defp answered_by_puma(port, upstream, request) do
    client = connect(port)
    send_raw(client, request)
    puma = accept(upstream)
    {head, _rest} = read_head(puma)
    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npuma")
    assert {200, _headers, "puma"} = read_response(client)
    {request_line(head), header(head, "cookie")}
  end

  test "Phoenix answers the list for a signed-in user", ctx do
    client = connect(serve())
    send_raw(client, request("/trips", ctx.cookie))
    assert {200, _headers, body} = read_response(client)
    assert body =~ "data-phx-main"
  end

  test "a non-string page goes to Puma with the Rails cookie", ctx do
    assert {line, [cookie]} =
             answered_by_puma(serve(), ctx.upstream, request("/trips?page%5B%5D=2", ctx.cookie))

    assert line == "GET /trips?page%5B%5D=2 HTTP/1.1"
    assert "_dawarich_session=" <> _ = cookie
  end

  test "a gate that cannot read the database hands the request to Puma", ctx do
    port = serve()
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, :manual)

    assert {"GET /trips HTTP/1.1", [_cookie]} =
             answered_by_puma(port, ctx.upstream, request("/trips", ctx.cookie))
  end
end
