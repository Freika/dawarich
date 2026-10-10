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
    previous_mode = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")
    on_exit(fn ->
      if previous_mode, do: System.put_env("DAWARICH_RAILS", previous_mode), else: System.delete_env("DAWARICH_RAILS")
    end)
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

  defp native_response(ctx, port, target, cookie, status, extra \\ "") do
    before = Dawarich.Repo.query!("SELECT count(*) FROM achievement_progresses WHERE user_id=79301").rows
    client = connect(port)
    send_raw(client, request("GET", target, cookie, extra))
    assert {^status, _, body} = read_response(client)
    refute body == "puma"
    assert Dawarich.Repo.query!("SELECT count(*) FROM achievement_progresses WHERE user_id=79301").rows == before
    assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
  end

  test "native achievement guests go to sign-in without forwarding", ctx do
    port = serve()
    for target <- ~w(/achievements /achievements/country_de),
      do: native_response(ctx, port, target, nil, 302)
  end

  test "native achievement queries normalize unknown keys and malformed shapes without effects", ctx do
    port = serve()
    for target <- ~w(/achievements?unexpected=1 /achievements/country_de?q=a&utf8=1 /achievements?q%5B%5D=a /achievements/country_de?status%5Ba%5D=b /achievements?page%5B%5D=2 /achievements/continent_europe?page=99999999999999999999 /achievements/country_de?page=1000000000001x),
      do: native_response(ctx, port, target, ctx.cookie, 200)
    for target <- ~w(/achievements/country_de?q=%FF /achievements?locale=%C3),
      do: native_response(ctx, port, target, ctx.cookie, 422)
  end

  test "native achievement missing and parent keys have bounded collection destinations", ctx do
    port = serve()
    for target <- ~w(/achievements/explorer_atlantis /achievements/Country_de /achievements/border_hopper /achievements/country_fr /achievements/country_aq),
      do: native_response(ctx, port, target, ctx.cookie, 302)
  end

  test "native achievement unsupported representations refuse without forwarding", ctx do
    port = serve()
    for target <- ~w(/achievements.json /achievements/country_de.json /achievements?format=json),
      do: native_response(ctx, port, target, ctx.cookie, if(target == "/achievements.json", do: 404, else: 422))
    for target <- ~w(/achievements /achievements/country_de),
      do: native_response(ctx, port, target, ctx.cookie, 422, "Accept: application/json\r\n")
  end

  test "unsupported achievement writes go to Puma", ctx do
    System.delete_env("DAWARICH_RAILS")
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
    System.delete_env("DAWARICH_RAILS")
    port = serve()
    target = "/achievements/country_de?q=Germany&status=all"
    answered_by_phoenix(port, request(target, ctx.cookie))

    Application.put_env(:dawarich, :rails_routes, ["achievements"])
    assert_puma(ctx, port, [target, "/achievements"])
  end
end
