defmodule DawarichWeb.Api.PlanEndpointTest do
  use Dawarich.ApiEndpointCase

  alias DawarichWeb.Api.PlanController

  @moduletag :capture_log

  @key "phoenix-a4-plan-key"
  @full ~s({"heatmap":true,"fog_of_war":true,"scratch_map":true,"globe_view":true,"integrations":true,"write_api":true,"sharing":true,"full_digest":true,"data_window":null})

  defp bearer(key \\ @key),
    do: [{"Authorization", "Bearer #{key}"}, {"Accept", "application/json"}]

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

      if key == "phoenix-a4-enum" do
        assert {500, _, ~s({"status":500,"error":"Internal Server Error"})} =
                 read_response(client)
      else
        assert {200, _, body} = read_response(client)
        assert Jason.decode!(body)["active_until"] == "2027-01-01T01:00:00+01:00"
      end

      no_upstream!(upstream)
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
      assert {200, _, body} = read_response(client)
      assert Jason.decode!(body)["plan"] == "pro"
      no_upstream!(upstream)
    end
  end

  test "HEAD, the .json suffix, /health and /ready stay on Rails", %{
    port: port,
    upstream: upstream
  } do
    routes = Application.get_env(:dawarich, :rails_routes, [])
    Application.put_env(:dawarich, :rails_routes, ["health", "ready"])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, routes) end)
    user!(%{api_key: @key})

    for {method, target} <- [
          {"HEAD", "/api/v1/plan"},
          {"GET", "/api/v1/plan.json"},
          {"GET", "/api/v1/health"},
          {"GET", "/api/v1/ready"}
        ] do
      client = request(port, target, bearer(), method)

      expected = if target == "/api/v1/ready", do: 503, else: 200
      assert {^expected, _, body} = read_response(client, method: method)
      if method == "HEAD", do: assert(body == "")
      no_upstream!(upstream)
    end
  end

  test "the answered line is tagged [api] and carries the final status, 304 included", %{
    port: port
  } do
    user!(%{api_key: @key})

    log =
      with_info_log(fn ->
        assert {200, first, _} = port |> request("/api/v1/plan", bearer()) |> read_response()
        [etag] = values(first, "etag")

        assert {304, _, ""} =
                 port
                 |> request("/api/v1/plan", bearer() ++ [{"If-None-Match", etag}])
                 |> read_response()
      end)

    assert log =~ ~r/\[api\] GET \/api\/v1\/plan 200 \d+ms request_id=\[FILTERED\]/
    assert log =~ ~r/\[api\] GET \/api\/v1\/plan 304 \d+ms request_id=\[FILTERED\]/
  end

  test "a hand-off to Rails logs at info, tagged [api]", %{port: port, upstream: upstream} do
    user!(%{api_key: "phoenix-a4-enum-log", plan: 7})

    log =
      with_info_log(fn ->
        client = request(port, "/api/v1/plan", bearer("phoenix-a4-enum-log"))

        assert {500, _, ~s({"status":500,"error":"Internal Server Error"})} =
                 read_response(client)

        no_upstream!(upstream)
      end)

    refute log =~ "handed to Rails"
  end

  test "a DB error raised while gathering fields hands off to Rails instead of crashing", %{
    upstream: upstream
  } do
    api_user = %{
      plan: 1,
      status: 1,
      subscription_source: 0,
      active_until: ~N[2099-01-01 00:00:00],
      timezone: nil
    }

    conn =
      Plug.Test.conn(:get, "/api/v1/plan")
      |> Plug.Conn.put_req_header("accept", "application/json")
      |> Plug.Conn.assign(:api_user, api_user)
      |> Plug.Conn.assign(:api_tag, "api")
      |> Plug.Conn.put_private(:dawarich_raw_body, "")
      |> Plug.Conn.put_private(:dawarich_native_api, true)

    Ecto.Adapters.SQL.Sandbox.checkin(Repo)

    log =
      with_info_log(fn ->
        result = PlanController.call(conn, :show)
        assert result.halted
        assert result.status == 500
        assert result.resp_body == ~s({"status":500,"error":"Internal Server Error"})
        no_upstream!(upstream)
      end)

    refute log =~ "handed to Rails"
  end
end
