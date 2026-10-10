defmodule DawarichWeb.MapFramesEndpointTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP

  alias Dawarich.Test.FrameSeeds, as: S
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)
    %{upstream: upstream, user: S.user!(7031)}
  end

  test "a residency year with tied countries is native without a Puma request", ctx do
    for {id, day, country} <- [
          {7891, ~U[2026-03-21 12:00:00Z], "Atlantis"},
          {7892, ~U[2026-03-22 12:00:00Z], "Narnia"}
        ],
        do: S.point!(ctx.user.id, id, DateTime.to_unix(day), %{country_name: country})

    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    client = connect(port)
    cookie = RailsUser.cookie(RailsUser.session(ctx.user.id))

    send_raw(
      client,
      "GET /map/residency?year=2026 HTTP/1.1\r\nHost: a\r\nAccept: text/html, application/xhtml+xml\r\n" <>
        "Cookie: _dawarich_session=#{cookie}\r\n\r\n"
    )

    assert {200, headers, body} = read_response(client)
    assert body =~ "Atlantis"
    assert body =~ "Narnia"
    assert {"content-type", "text/html; charset=utf-8"} in headers
    assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
  end
end
