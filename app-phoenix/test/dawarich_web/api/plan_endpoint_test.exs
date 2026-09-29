defmodule DawarichWeb.Api.PlanEndpointTest do
  use Dawarich.IngestCase, async: false
  import Dawarich.Test.RawHTTP

  @key "phoenix-a4-plan-key"
  @full ~s({"heatmap":true,"fog_of_war":true,"scratch_map":true,"globe_view":true,"integrations":true,"write_api":true,"sharing":true,"full_digest":true,"data_window":null})

  setup do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    previous = System.get_env("TIME_ZONE")
    System.delete_env("TIME_ZONE")

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, nil)
      Enum.each(~w(SELF_HOSTED DAWARICH_RAILS_SLICES), &System.delete_env/1)
      if previous, do: System.put_env("TIME_ZONE", previous)
    end)

    %{port: port, upstream: upstream}
  end

  defp request(port, target, headers, method \\ "GET") do
    client = connect(port)

    send_raw(client, [
      "#{method} #{target} HTTP/1.1\r\nHost: localhost\r\n",
      Enum.map(headers, fn {n, v} -> "#{n}: #{v}\r\n" end),
      "\r\n"
    ])

    client
  end

  defp bearer(key \\ @key),
    do: [{"Authorization", "Bearer #{key}"}, {"Accept", "application/json"}]

  defp puma(upstream, body \\ "rails") do
    socket = accept(upstream)
    {head, _rest} = read_head(socket)
    reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}")
    request_line(head)
  end

  defp no_upstream!(upstream),
    do: assert({:error, :timeout} = :gen_tcp.accept(upstream.listen, 0))

  test "Phoenix answers the mobile app's request with Rails' bytes", %{
    port: port,
    upstream: upstream
  } do
    user!(%{
      api_key: @key,
      active_until: ~N[3026-07-01 12:00:00.123456],
      settings: %{"timezone" => "Europe/Berlin"}
    })

    assert {200, headers, body} = port |> request("/api/v1/plan", bearer()) |> read_response()

    assert body ==
             ~s({"plan":"pro","effective_plan":"pro","status":"active","subscription_source":"none","active_until":"3026-07-01T13:00:00+01:00","features":#{@full}})

    assert values(headers, "content-type") == ["application/json; charset=utf-8"]
    assert values(headers, "vary") == ["Accept"]
    assert values(headers, "x-dawarich-response") == ["Hey, I'm alive and authenticated!"]
    assert [_etag] = values(headers, "etag")
    no_upstream!(upstream)
  end

  test "pending, inactive and expired users get their plan; every enum label, a null status and a null date",
       %{port: port} do
    user!(%{
      api_key: "phoenix-a4-p",
      status: 3,
      plan: 0,
      subscription_source: 2,
      active_until: nil
    })

    user!(%{
      api_key: "phoenix-a4-i",
      status: 0,
      plan: 2,
      subscription_source: 3,
      active_until: ~N[2099-01-01 00:00:00],
      settings: %{"timezone" => "UTC"}
    })

    user!(%{
      api_key: "phoenix-a4-e",
      status: nil,
      subscription_source: 1,
      active_until: ~N[2001-01-01 00:00:00],
      settings: %{"timezone" => "Europe/Berlin"}
    })

    assert {200, _,
            ~s({"plan":"lite","effective_plan":"lite","status":"pending_payment","subscription_source":"apple_iap","active_until":null,) <>
              _} =
             port |> request("/api/v1/plan", bearer("phoenix-a4-p")) |> read_response()

    assert {200, _,
            ~s({"plan":"family","effective_plan":"family","status":"inactive","subscription_source":"google_play","active_until":"2099-01-01T00:00:00Z",) <>
              _} =
             port |> request("/api/v1/plan", bearer("phoenix-a4-i")) |> read_response()

    assert {200, _,
            ~s({"plan":"pro","effective_plan":"pro","status":null,"subscription_source":"paddle","active_until":"2001-01-01T01:00:00+01:00",) <>
              _} =
             port |> request("/api/v1/plan", bearer("phoenix-a4-e")) |> read_response()
  end

  test "no key or an unknown key: Rails' 401 head", %{port: port} do
    assert {401, headers, ""} = port |> request("/api/v1/plan", []) |> read_response()
    assert values(headers, "content-type") == ["text/html"]

    assert {401, _, ""} =
             port |> request("/api/v1/plan", bearer("phoenix-a4-nobody")) |> read_response()
  end

  test "If-None-Match equal to the ETag answers 304 with no body, no content type and no length",
       %{port: port, upstream: upstream} do
    user!(%{api_key: @key})
    assert {200, first, _} = port |> request("/api/v1/plan", bearer()) |> read_response()
    [etag] = values(first, "etag")

    assert {304, headers, ""} =
             port
             |> request("/api/v1/plan", bearer() ++ [{"If-None-Match", etag}])
             |> read_response()

    assert {[], [], [etag]} ==
             {values(headers, "content-type"), values(headers, "content-length"),
              values(headers, "etag")}

    assert values(headers, "cache-control") == ["max-age=0, private, must-revalidate"]
    no_upstream!(upstream)
  end

  test "an unknown enum value or a zone Phoenix does not own is handed to Rails", %{
    port: port,
    upstream: upstream
  } do
    user!(%{api_key: "phoenix-a4-enum", plan: 7})

    user!(%{
      api_key: "phoenix-a4-alias",
      active_until: ~N[2027-01-01 00:00:00],
      settings: %{"timezone" => "Mars/Olympus_Mons"}
    })

    for key <- ~w(phoenix-a4-enum phoenix-a4-alias) do
      client = request(port, "/api/v1/plan", bearer(key))
      assert puma(upstream) == "GET /api/v1/plan HTTP/1.1"
      assert {200, _, "rails"} = read_response(client)
    end
  end

  for {name, env} <- [
        {"Cloud", {"SELF_HOSTED", "false"}},
        {"the kill switch", {"DAWARICH_RAILS_SLICES", "api_foundation"}}
      ] do
    test "#{name} keeps /plan on Rails", %{port: port, upstream: upstream} do
      {var, value} = unquote(Macro.escape(env))
      System.put_env(var, value)
      user!(%{api_key: @key})
      client = request(port, "/api/v1/plan", bearer())
      assert puma(upstream) == "GET /api/v1/plan HTTP/1.1"
      assert {200, _, "rails"} = read_response(client)
    end
  end

  test "HEAD, the .json suffix, /health and /ready stay on Rails", %{
    port: port,
    upstream: upstream
  } do
    user!(%{api_key: @key})

    for {method, target} <- [
          {"HEAD", "/api/v1/plan"},
          {"GET", "/api/v1/plan.json"},
          {"GET", "/api/v1/health"},
          {"GET", "/api/v1/ready"}
        ] do
      client = request(port, target, bearer(), method)

      assert puma(upstream, if(method == "HEAD", do: "", else: "rails")) ==
               "#{method} #{target} HTTP/1.1"

      assert {200, _, _} = read_response(client, method: method)
    end
  end
end
