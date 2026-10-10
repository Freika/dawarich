defmodule DawarichWeb.PlacesGateEndpointTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log
  @endpoint DawarichWeb.Endpoint

  import Dawarich.Test.RawHTTP
  import ExUnit.CaptureLog
  import Phoenix.ConnTest

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

  test "a query part without = goes to Puma, whose parser reads it as nil", ctx do
    port = serve()

    for target <- ~w(/places?page /places?view /places?page=2&view) do
      assert {line, [_cookie]} = answered_by_puma(port, ctx.upstream, request(target, ctx.cookie))
      assert line == "GET #{target} HTTP/1.1"
    end
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

  @frame [{"Accept", "text/html, application/xhtml+xml"}, {"Turbo-Frame", "place-drawer"}]

  test "Phoenix answers the drawer frame", ctx do
    client = connect(serve())
    send_raw(client, request("/places/842101", ctx.cookie, @frame))
    assert {200, headers, body} = read_response(client)
    assert values(headers, "content-type") == ["text/html; charset=utf-8"]
    assert values(headers, "vary") == ["Accept"]
    assert body =~ ~r{\A<turbo-frame id="place-drawer">}
  end

  test "an unframed request goes to Puma", ctx do
    assert {"GET /places/842101 HTTP/1.1", [_cookie]} =
             answered_by_puma(
               serve(),
               ctx.upstream,
               request("/places/842101", ctx.cookie, [hd(@frame), {"X-Dawarich-Client", "ios"}])
             )
  end

  test "a second frame name or a repeated header goes to Puma", ctx do
    port = serve()
    accept = hd(@frame)

    for headers <- [
          [accept, {"Turbo-Frame", "other"}],
          [accept, {"Turbo-Frame", "place-drawer"}, {"Turbo-Frame", "other"}]
        ] do
      assert {"GET /places/842101 HTTP/1.1", [_cookie]} =
               answered_by_puma(
                 port,
                 ctx.upstream,
                 request("/places/842101", ctx.cookie, headers)
               )
    end
  end

  test "a query string or X-Dawarich-Client goes to Puma", ctx do
    port = serve()

    for {target, headers} <- [
          {"/places/842101?locale=de", @frame},
          {"/places/842101?x=1", @frame},
          {"/places/842101", @frame ++ [{"X-Dawarich-Client", "ios"}]}
        ] do
      assert {line, [_cookie]} =
               answered_by_puma(port, ctx.upstream, request(target, ctx.cookie, headers))

      assert line == "GET #{target} HTTP/1.1"
    end
  end

  test "a foreign or missing place goes to Puma before routing", ctx do
    user!(8423)
    S.place!(8423, 842_301, "Fremd")
    Logger.put_module_level(DawarichWeb.Api.Body, :info)
    on_exit(fn -> Logger.delete_module_level(DawarichWeb.Api.Body) end)
    port = serve()

    for target <- ~w(/places/842301 /places/842199) do
      log =
        capture_log(fn ->
          assert {line, [_cookie]} =
                   answered_by_puma(port, ctx.upstream, request(target, ctx.cookie, @frame))

          assert line == "GET #{target} HTTP/1.1"
        end)

      refute log =~ "place drawer changed after the gate"
    end
  end

  test "a drawer that leaves after the gate is replayed under the places log tag", ctx do
    Logger.put_module_level(DawarichWeb.Api.Body, :info)
    on_exit(fn -> Logger.delete_module_level(DawarichWeb.Api.Body) end)

    conn =
      build_conn(:get, "/places/842199")
      |> Plug.Conn.put_req_header("accept", "text/html, application/xhtml+xml")
      |> Map.put(:path_params, %{"id" => "842199"})
      |> Plug.Conn.assign(:rails_session, RailsUser.session(8421))
      |> Plug.Conn.assign(:current_user, Dawarich.Accounts.get(8421))
      |> Plug.Conn.assign(:locale, "en")

    puma =
      Task.async(fn ->
        socket = accept(ctx.upstream)
        {head, _rest} = read_head(socket)
        reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npuma")
        request_line(head)
      end)

    log = capture_log(fn -> assert DawarichWeb.MapFrames.call(conn, :place).status == 200 end)

    assert Task.await(puma) == "GET /places/842199 HTTP/1.1"
    assert log =~ "[places] /places/842199 handed to Rails: place drawer changed after the gate"
  end

  test "unsupported ids and writes go to Puma while nearby is native", ctx do
    saved = System.get_env("PHOTON_API_HOST")
    System.put_env("PHOTON_API_HOST", "photon.example.invalid")

    on_exit(fn ->
      if saved,
        do: System.put_env("PHOTON_API_HOST", saved),
        else: System.delete_env("PHOTON_API_HOST")
    end)

    S.place!(8421, 1_000_000_000_000_000_001, "Lang")
    port = serve()

    for target <- [
          "/places/12abc",
          "/places/1000000000000000001",
          "/places/842101/edit"
        ] do
      assert {line, [_cookie]} =
               answered_by_puma(port, ctx.upstream, request(target, ctx.cookie, @frame))

      assert line == "GET #{target} HTTP/1.1"
    end

    start_supervised!(Dawarich.Geocoding.FakeHttp)
    start_supervised!(hd(Dawarich.Redis.child_specs()))

    Dawarich.Geocoding.FakeHttp.stub(
      "http://photon.example.invalid/reverse?distance_sort=true&lang=en&lat=51.34&limit=5&lon=12.37&radius=0.5",
      200,
      Jason.encode!(%{"type" => "FeatureCollection", "features" => []})
    )

    client = connect(port)
    send_raw(client, request("/places/nearby?latitude=51.34&longitude=12.37", ctx.cookie, @frame))
    assert {200, _headers, body} = read_response(client)
    assert body =~ "No nearby places found"

    body = "_method=patch&place%5Bnote%5D=x"

    for {method, target} <- [
          {"POST", "/places"},
          {"PATCH", "/places/842101"},
          {"PUT", "/places/842101"},
          {"DELETE", "/places/842101"}
        ] do
      raw =
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\nCookie: #{ctx.cookie}\r\n" <>
          "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: #{byte_size(body)}\r\n\r\n" <>
          body

      client = connect(port)
      send_raw(client, raw)
      puma = accept(ctx.upstream)
      {head, rest} = read_head(puma)
      assert request_line(head) == "#{method} #{target} HTTP/1.1"
      assert read_at_least(puma, rest, byte_size(body)) == body
      reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npuma")
      assert {200, _headers, "puma"} = read_response(client)
    end
  end

  test "a signed-out frame request is redirected by Phoenix" do
    conn =
      Enum.reduce(@frame, build_conn(), fn {name, value}, conn ->
        Plug.Conn.put_req_header(conn, String.downcase(name), value)
      end)
      |> get("/places/842101")

    assert redirected_to(conn, 302) == "http://www.example.com/users/sign_in"

    [_, value] =
      Regex.run(
        ~r/_dawarich_session=([^;]+)/,
        conn |> Plug.Conn.get_resp_header("set-cookie") |> hd()
      )

    staged =
      build_conn()
      |> put_req_cookie("_dawarich_session", value)
      |> DawarichWeb.RailsAuth.call([])

    assert staged.assigns.rails_session["user_return_to"] == "/places/842101"
  end
end
