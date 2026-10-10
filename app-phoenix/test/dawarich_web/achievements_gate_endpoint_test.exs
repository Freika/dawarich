defmodule DawarichWeb.AchievementsGateEndpointTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP

  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    Dawarich.Test.AchievementSilhouettes.clear()
    on_exit(&Dawarich.Test.AchievementSilhouettes.clear/0)
    upstream = listen()
    saved = Map.new(~w(rails_upstream rails_routes)a, &{&1, Application.fetch_env(:dawarich, &1)})
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    on_exit(fn ->
      for {key, value} <- saved do
        case value do
          {:ok, configured} -> Application.put_env(:dawarich, key, configured)
          :error -> Application.delete_env(:dawarich, key)
        end
      end
    end)

    RailsUser.insert!(%{
      id: 79_301,
      email: "a10-gate@example.invalid",
      settings: %{"timezone" => "Europe/Berlin", "locale" => "en"}
    })

    %{
      upstream: upstream,
      cookie: "_dawarich_session=" <> RailsUser.cookie(RailsUser.session(79_301))
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

  defp request(method \\ "GET", target, cookie, extra \\ "") do
    body = if method == "GET", do: "", else: "authenticity_token=x"
    length = if body == "", do: "", else: "Content-Length: #{byte_size(body)}\r\n"
    cookie = if cookie, do: "Cookie: #{cookie}\r\n", else: ""
    "#{method} #{target} HTTP/1.1\r\nHost: a\r\n#{cookie}#{extra}#{length}\r\n#{body}"
  end

  defp answered_by_phoenix(port, request) do
    client = connect(port)
    send_raw(client, request)
    assert {200, headers, body} = read_response(client)
    assert body =~ "data-phx-main"
    headers
  end

  defp answered_by_puma(port, upstream, request) do
    client = connect(port)
    send_raw(client, request)
    puma = accept(upstream)
    {head, _rest} = read_head(puma)
    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npuma")
    assert {200, _headers, "puma"} = read_response(client)
    {request_line(head), header(head, "cookie")}
  end

  defp assert_puma(ctx, port, targets, method \\ "GET", extra \\ "") do
    for target <- targets do
      assert {line, [cookie]} =
               answered_by_puma(port, ctx.upstream, request(method, target, ctx.cookie, extra))

      assert line == "#{method} #{target} HTTP/1.1"
      assert cookie == ctx.cookie
    end
  end

  test "Phoenix answers signed-in collection and detail pages on Cloud too, HEAD included", ctx do
    cloud = %{
      "SELF_HOSTED" => "false",
      "JWT_SECRET_KEY" => "phoenix-a10-jwt-fixture-not-a-secret"
    }

    saved = Map.new(cloud, fn {name, _} -> {name, System.get_env(name)} end)
    System.put_env(cloud)

    on_exit(fn ->
      for {name, value} <- saved,
          do: if(value, do: System.put_env(name, value), else: System.delete_env(name))
    end)

    port = serve()

    for target <-
          ~w(/achievements /achievements/country_de?q=x&status=locked&page=2 /achievements/continent_europe?locale=de&page=abc /achievements/continent_europe?q=germ&status=in_progress&commit=Apply) do
      headers = answered_by_phoenix(port, request(target, ctx.cookie))
      assert values(headers, "x-dawarich-handler") == []
    end

    client = connect(port)
    send_raw(client, request("HEAD", "/achievements", ctx.cookie))
    assert {200, _headers, _body} = read_response_head(client)
  end

  test "a guest's page request goes to Puma unchanged", ctx do
    port = serve()

    for target <- ~w(/achievements /achievements/country_de) do
      assert answered_by_puma(port, ctx.upstream, request(target, nil)) ==
               {"GET #{target} HTTP/1.1", []}
    end
  end

  test "a query key outside q, status, page and locale goes to Puma", ctx do
    assert_puma(ctx, serve(), ~w(/achievements?unexpected=1 /achievements/country_de?q=a&utf8=1))
  end

  test "a query value that is not a string goes to Puma", ctx do
    assert_puma(
      ctx,
      serve(),
      ~w(/achievements?q%5B%5D=a /achievements/country_de?status%5Ba%5D=b /achievements?page%5B%5D=2)
    )
  end

  test "a query value that is not UTF-8 goes to Puma", ctx do
    assert_puma(ctx, serve(), ~w(/achievements/country_de?q=%FF /achievements?locale=%C3))
  end

  test "a page number Rails cannot offset goes to Puma", ctx do
    assert_puma(
      ctx,
      serve(),
      ~w(/achievements/continent_europe?page=99999999999999999999 /achievements/country_de?page=1000000000001x)
    )
  end

  test "an achievement key Rails does not render goes to Puma", ctx do
    assert_puma(ctx, serve(), ~w(/achievements/explorer_atlantis /achievements/Country_de))
  end

  test "a key Rails redirects or answers with 404 goes to Puma", ctx do
    assert_puma(
      ctx,
      serve(),
      ~w(/achievements/border_hopper /achievements/country_fr /achievements/country_aq)
    )
  end

  test "a formatted request goes to Puma", ctx do
    port = serve()

    assert_puma(
      ctx,
      port,
      ~w(/achievements.json /achievements/country_de.json /achievements?format=json)
    )

    assert_puma(
      ctx,
      port,
      ~w(/achievements /achievements/country_de),
      "GET",
      "Accept: application/json\r\n"
    )
  end

  test "unsupported achievement writes go to Puma", ctx do
    port = serve()

    for method <- ~w(POST PATCH PUT DELETE) do
      assert_puma(
        ctx,
        port,
        ~w(/achievements /achievements/country_de /achievements/country_de/toggle_sharing),
        method,
        "Content-Type: application/x-www-form-urlencoded\r\n"
      )
    end

    assert_puma(
      ctx,
      port,
      ~w(/achievements/unlocks/next /achievements/unlocks/7/seen /achievements/unlocks/dismiss),
      "POST",
      "Content-Type: application/x-www-form-urlencoded\r\n"
    )
  end

  test "DAWARICH_RAILS_ROUTES=achievements hands a page Phoenix answers to Puma unchanged", ctx do
    port = serve()
    target = "/achievements/country_de?q=Germany&status=all"
    answered_by_phoenix(port, request(target, ctx.cookie))

    Application.put_env(:dawarich, :rails_routes, ["achievements"])
    assert_puma(ctx, port, [target, "/achievements"])
  end
end
