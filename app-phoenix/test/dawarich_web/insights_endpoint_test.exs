defmodule DawarichWeb.InsightsEndpointTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP

  alias Dawarich.Test.{RailsUser, TripsSeeds}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    routes = Application.get_env(:dawarich, :rails_routes, [])

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, nil)
      Application.put_env(:dawarich, :rails_routes, routes)
    end)

    TripsSeeds.user!(9301, %{"timezone" => "Europe/Berlin", "maps" => %{"distance_unit" => "km"}})

    %{
      upstream: upstream,
      port: serve(),
      cookie: "_dawarich_session=" <> RailsUser.cookie(RailsUser.session(9301))
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

  defp request(target, headers, method \\ "GET") do
    lines = Enum.map(headers, fn {name, value} -> "#{name}: #{value}\r\n" end)
    "#{method} #{target} HTTP/1.1\r\nHost: a\r\n#{lines}Content-Length: 0\r\n\r\n"
  end

  defp phoenix(port, request) do
    client = connect(port)
    send_raw(client, request)
    read_response(client)
  end

  defp puma(port, upstream, request) do
    client = connect(port)
    send_raw(client, request)
    puma = accept(upstream)
    {head, _rest} = read_head(puma)
    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npuma")
    assert {200, _headers, "puma"} = read_response(client)
    {request_line(head), header(head, "cookie")}
  end

  test "a signed-in Turbo frame request gets the details frame in Turbo's minimal layout", ctx do
    frame = [{"Cookie", ctx.cookie}, {"Turbo-Frame", "insights_details"}]

    assert {200, _headers, body} =
             phoenix(ctx.port, request("/insights/details?year=all", frame))

    assert String.starts_with?(body, "<html>")
    assert body =~ ~s(<turbo-frame id="insights_details">)

    for absent <- ["<!DOCTYPE", "<title", "<script", "class=\"navbar"],
        do: refute(body =~ absent, "frame response contains #{absent}")
  end

  test "a direct signed-in request gets the app layout with the navbar", ctx do
    assert {200, _headers, body} =
             phoenix(ctx.port, request("/insights/details?year=all", [{"Cookie", ctx.cookie}]))

    assert body =~ "<!DOCTYPE html>"
    assert body =~ ~s(<div class="navbar bg-base-100 h-16">)
    assert body =~ ~s(<turbo-frame id="insights_details">)
  end

  test "a signed-in visit to / is redirected to the map by Phoenix", ctx do
    assert {302, headers, ""} = phoenix(ctx.port, request("/", [{"Cookie", ctx.cookie}]))
    assert values(headers, "location") == ["http://a/map/v2"]
  end

  test "guest requests for / and the details go to Puma intact", ctx do
    for target <- ["/", "/insights/details?year=2024"] do
      assert {line, []} = puma(ctx.port, ctx.upstream, request(target, []))
      assert line == "GET #{target} HTTP/1.1"
    end
  end

  test "writes, formats, JSON and XHR go to Puma with the Rails cookie", ctx do
    cookie = {"Cookie", ctx.cookie}

    for {method, target, headers} <- [
          {"POST", "/insights/details", [cookie]},
          {"GET", "/insights/details?format=csv", [cookie]},
          {"GET", "/insights/details.csv", [cookie]},
          {"GET", "/insights/details", [cookie, {"Accept", "application/json"}]},
          {"GET", "/insights/details", [cookie, {"X-Requested-With", "XMLHttpRequest"}]}
        ] do
      assert {line, [forwarded]} = puma(ctx.port, ctx.upstream, request(target, headers, method))
      assert line == "#{method} #{target} HTTP/1.1"
      assert forwarded == ctx.cookie
    end
  end

  test "the insights kill switch hands / and the details to Puma", ctx do
    Application.put_env(:dawarich, :rails_routes, ["insights"])

    for target <- ["/", "/insights/details?year=all"] do
      assert {line, [_cookie]} =
               puma(ctx.port, ctx.upstream, request(target, [{"Cookie", ctx.cookie}]))

      assert line == "GET #{target} HTTP/1.1"
    end
  end

  test "a non-string year or month goes to Puma", ctx do
    for target <- [
          "/insights/details?year%5B%5D=2024",
          "/insights/details?year=2024&month%5Bx%5D=4"
        ] do
      assert {line, [_cookie]} =
               puma(ctx.port, ctx.upstream, request(target, [{"Cookie", ctx.cookie}]))

      assert line == "GET #{target} HTTP/1.1"
    end
  end
end
