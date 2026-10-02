defmodule DawarichWeb.PlacesGateEndpointTest do
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
    user!(8421)
    for n <- 1..3, do: S.place!(8421, 842_100 + n, "Ort #{n}")

    %{upstream: upstream, cookie: cookie(8421)}
  end

  defp user!(id, settings \\ %{"timezone" => "Europe/Berlin"}),
    do: S.user!(id, settings, %{email: "a84-#{id}@example.invalid", api_key: "a84-k-#{id}"})

  defp cookie(id), do: "_dawarich_session=" <> RailsUser.cookie(RailsUser.session(id))

  defp serve do
    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    port
  end

  defp request(target, cookie, headers \\ []),
    do:
      "GET #{target} HTTP/1.1\r\nHost: a\r\nCookie: #{cookie}\r\n" <>
        Enum.map_join(headers, &"#{elem(&1, 0)}: #{elem(&1, 1)}\r\n") <> "\r\n"

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
    send_raw(client, request("/places", ctx.cookie))
    assert {200, _headers, body} = read_response(client)
    assert body =~ "data-phx-main"
  end

  test "a non-string page goes to Puma with the Rails cookie", ctx do
    assert {line, [cookie]} =
             answered_by_puma(serve(), ctx.upstream, request("/places?page%5B%5D=2", ctx.cookie))

    assert line == "GET /places?page%5B%5D=2 HTTP/1.1"
    assert "_dawarich_session=" <> _ = cookie
  end

  test "an account whose zone PostgreSQL lacks goes to Puma", ctx do
    user!(8422, %{"timezone" => "Mars/Phobos"})
    S.place!(8422, 842_201, "Mars")

    assert {"GET /places HTTP/1.1", [_cookie]} =
             answered_by_puma(serve(), ctx.upstream, request("/places", cookie(8422)))
  end

  test "a gate that cannot read the database hands the request to Puma", ctx do
    port = serve()
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, :manual)

    assert {"GET /places HTTP/1.1", [_cookie]} =
             answered_by_puma(port, ctx.upstream, request("/places", ctx.cookie))
  end

  test "the list's formats go to Puma", ctx do
    port = serve()

    for {target, headers} <- [
          {"/places.json", []},
          {"/places?format=json", []},
          {"/places", [{"X-Requested-With", "XMLHttpRequest"}]}
        ] do
      assert {line, [_cookie]} =
               answered_by_puma(port, ctx.upstream, request(target, ctx.cookie, headers))

      assert line == "GET #{target} HTTP/1.1"
    end
  end
end
