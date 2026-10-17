defmodule DawarichWeb.Api.StatsEndpointTest do
  use Dawarich.ApiEndpointCase
  import Dawarich.Test.StatsSeeds

  alias DawarichWeb.Api.{DigestsController, GeoController, StatsController}

  @moduletag :capture_log

  @key "phoenix-a4g2-key-endpoint"

  setup do
    Dawarich.FixtureCleanup.delete!(Dawarich.ScratchRepo, ~w(phoenix.stats_point_counts))
    :ok
  end

  defp bearer(key \\ @key),
    do: [{"Authorization", "Bearer #{key}"}, {"Accept", "application/json"}]

  defp owner!(attrs \\ %{}) do
    id = user!(Map.merge(%{api_key: @key, settings: %{"timezone" => "UTC"}}, attrs))
    stat!(id, %{year: 2024, month: 3, distance: 1000})
    digest!(id, %{year: 2023, updated_at: ~N[2025-01-02 03:04:05.678]})
    id
  end

  test "Phoenix answers the eight owned routes of a self-hosted user", %{
    port: port,
    upstream: upstream
  } do
    owner!()

    for target <-
          ~w(/api/v1/stats /api/v1/insights /api/v1/insights/details /api/v1/digests /api/v1/digests/2023
                     /api/v1/residency?year=2024 /api/v1/countries/visited_cities?start_at=1&end_at=2 /api/v1/flights) do
      assert {200, headers, _body} = port |> request(target, bearer()) |> read_response(), target

      assert {values(headers, "content-type"), values(headers, "x-dawarich-response")} ==
               {["application/json; charset=utf-8"], ["Hey, I'm alive and authenticated!"]},
             target
    end

    no_upstream!(upstream)
  end

  test "Rails' validators: insights' five minutes and its 304, the digest's Last-Modified, its 304, strict freshness, the 404",
       %{port: port} do
    owner!()

    assert {200, first, _} = port |> request("/api/v1/insights", bearer()) |> read_response()
    [etag] = values(first, "etag")
    assert values(first, "cache-control") == ["max-age=300, private"]

    assert {304, again, ""} =
             port
             |> request("/api/v1/insights", bearer() ++ [{"If-None-Match", etag}])
             |> read_response()

    assert {["max-age=300, private"], [etag], []} ==
             {values(again, "cache-control"), values(again, "etag"),
              values(again, "content-type")}

    stamp = "Thu, 02 Jan 2025 03:04:05 GMT"
    assert {200, shown, _} = port |> request("/api/v1/digests/2023", bearer()) |> read_response()

    assert {[stamp], ["max-age=3600, private"], []} ==
             {values(shown, "last-modified"), values(shown, "cache-control"),
              values(shown, "etag")}

    assert {304, fresh, ""} =
             port
             |> request("/api/v1/digests/2023", bearer() ++ [{"If-Modified-Since", stamp}])
             |> read_response()

    assert {[stamp], ["max-age=0, private, must-revalidate"], [], [], []} ==
             {values(fresh, "last-modified"), values(fresh, "cache-control"),
              values(fresh, "content-type"), values(fresh, "content-length"),
              values(fresh, "vary")}

    assert {200, _, _} =
             port
             |> request(
               "/api/v1/digests/2023",
               bearer() ++ [{"If-Modified-Since", "Wed, 01 Jan 2025 00:00:00 GMT"}]
             )
             |> read_response()

    assert {200, _, _} =
             port
             |> request(
               "/api/v1/digests/2023",
               bearer() ++ [{"If-Modified-Since", stamp}, {"If-None-Match", ~s(W/"x")}]
             )
             |> read_response()

    assert {404, missing, ~s({"error":"Record not found"})} =
             port |> request("/api/v1/digests/2022", bearer()) |> read_response()

    assert values(missing, "cache-control") == ["no-cache"]
  end

  test "no key is 401, pending payment 402, inactive and expired users read", %{port: port} do
    assert {401, _, ""} = port |> request("/api/v1/stats", []) |> read_response()

    user!(%{api_key: "phoenix-a4g2-key-pending", status: 3})

    assert {402, _,
            ~s({"error":"payment_required","message":"Complete your subscription to continue.","resume_url":null})} =
             port
             |> request("/api/v1/digests", bearer("phoenix-a4g2-key-pending"))
             |> read_response()

    user!(%{api_key: "phoenix-a4g2-key-inactive", status: 0})
    user!(%{api_key: "phoenix-a4g2-key-expired", active_until: ~N[2001-01-01 00:00:00]})

    for key <- ~w(phoenix-a4g2-key-inactive phoenix-a4g2-key-expired),
        do:
          assert(
            {200, _, _} = port |> request("/api/v1/digests", bearer(key)) |> read_response(),
            key
          )
  end

  test "visited_cities without its parameters: Rails' 400", %{port: port} do
    owner!()

    assert {400, _, ~s({"error":"Missing required parameters: start_at, end_at"})} =
             port |> request("/api/v1/countries/visited_cities", bearer()) |> read_response()

    assert {400, _, ~s({"error":"Missing required parameters: end_at"})} =
             port
             |> request("/api/v1/countries/visited_cities?start_at=1&end_at=", bearer())
             |> read_response()
  end

  test "permissive stats parameters terminate natively", %{port: port, upstream: upstream} do
    owner!()
    user!(%{api_key: "phoenix-a4g2-key-zone", settings: %{"timezone" => "europe/berlin"}})

    for {target, headers} <- [
          {"/api/v1/insights?distance_unit=furlong", bearer()},
          {"/api/v1/insights?year=abc", bearer()},
          {"/api/v1/residency?year=2045", bearer()},
          {"/api/v1/countries/visited_cities?start_at=yesterday&end_at=1", bearer()},
          {"/api/v1/flights?start_at=March%201", bearer()},
          {"/api/v1/digests/2023",
           bearer() ++ [{"If-Modified-Since", "Sunday, 06-Nov-94 08:49:37 GMT"}]},
          {"/api/v1/digests", bearer("phoenix-a4g2-key-zone")}
        ] do
      client = request(port, target, headers)

      {status, _, body} = read_response(client)
      decoded = Jason.decode!(body)

      cond do
        target == "/api/v1/insights?distance_unit=furlong" ->
          assert {status, decoded} == {500, %{"error" => "internal_server_error"}}

        target == "/api/v1/insights?year=abc" ->
          assert status == 200
          assert decoded["year"] == 0
          assert decoded["totals"]["totalDistance"] == 0

        target == "/api/v1/residency?year=2045" ->
          assert {status, decoded} ==
                   {500, %{"status" => 500, "error" => "Internal Server Error"}}

        target == "/api/v1/countries/visited_cities?start_at=yesterday&end_at=1" ->
          assert {status, decoded} == {200, %{"data" => []}}

        target == "/api/v1/flights?start_at=March%201" ->
          assert {status, decoded} == {200, %{"type" => "FeatureCollection", "features" => []}}

        target == "/api/v1/digests/2023" ->
          assert status == 200
          assert decoded["year"] == 2023

        true ->
          assert {status, decoded} == {200, %{"digests" => [], "availableYears" => []}}
      end

      no_upstream!(upstream)
    end
  end

  test "year-zero date filters terminate natively for visited_cities and flights",
       %{port: port, upstream: upstream} do
    owner!()

    for target <- [
          "/api/v1/countries/visited_cities?start_at=0000-01-01&end_at=1",
          "/api/v1/flights?start_at=0000-01-01"
        ] do
      client = request(port, target, bearer())
      {status, _, body} = read_response(client)

      expected =
        if String.contains?(target, "visited_cities"),
          do: {200, %{"data" => []}},
          else: {500, %{"error" => "internal_server_error"}}

      assert {status, Jason.decode!(body)} == expected
      no_upstream!(upstream)
    end
  end

  test "Cloud legacy reads, slice pins, HEAD, suffixes, digest constraints and mutations reach Puma",
       %{port: port, upstream: upstream} do
    owner!()

    for {method, target, env} <- [
          {"GET", "/api/v1/stats", {"SELF_HOSTED", "false"}},
          {"GET", "/api/v1/stats", {"DAWARICH_RAILS_SLICES", "api_stats"}},
          {"HEAD", "/api/v1/stats", nil},
          {"GET", "/api/v1/stats.json", nil},
          {"GET", "/api/v1/insights/details.json", nil},
          {"GET", "/api/v1/digests/new", nil},
          {"GET", "/api/v1/digests/2023.json", nil},
          {"GET", "/api/v1/digests/23", nil},
          {"POST", "/api/v1/digests?year=2023", nil},
          {"DELETE", "/api/v1/digests/2023", nil},
          {"GET", "/api/v1/countries/borders", {"DAWARICH_RAILS_SLICES", "api_map_reads"}},
          {"GET", "/api/v1/countries/visited?start_at=1&end_at=2",
           {"DAWARICH_RAILS_SLICES", "api_map_reads"}}
        ] do
      Enum.each(~w(SELF_HOSTED DAWARICH_RAILS_SLICES), &System.delete_env/1)
      with {name, value} <- env, do: System.put_env(name, value)
      client = request(port, target, [{"Accept", "application/json"}], method)

      expected = if target in ["/api/v1/digests/new", "/api/v1/digests/23"], do: 404, else: 401

      assert {^expected, _, body} = read_response(client, method: method)
      if method == "HEAD", do: assert(body == "")
      no_upstream!(upstream)
    end

    System.delete_env("DAWARICH_RAILS_SLICES")

    for hosted <- ["true", "false"] do
      System.put_env("SELF_HOSTED", hosted)

      for target <- ~w(/api/v1/countries/borders /api/v1/countries/visited?start_at=1&end_at=2) do
        assert {401, headers, ""} =
                 port |> request(target, [{"Accept", "application/json"}]) |> read_response()

        assert values(headers, "x-dawarich-response") == ["Hey, I'm alive!"]
      end
    end

    no_upstream!(upstream)
  end

  test "terminal stats answers log final status and Last-Modified 304",
       %{port: port, upstream: upstream} do
    owner!()
    stamp = "Thu, 02 Jan 2025 03:04:05 GMT"

    log =
      with_info_log(fn ->
        assert {200, _, _} = port |> request("/api/v1/stats", bearer()) |> read_response()

        assert {304, _, ""} =
                 port
                 |> request("/api/v1/digests/2023", bearer() ++ [{"If-Modified-Since", stamp}])
                 |> read_response()

        client = request(port, "/api/v1/insights?year=abc", bearer())

        assert {200, _, body} = read_response(client)
        assert Jason.decode!(body)["year"] == 0

        no_upstream!(upstream)
      end)

    assert log =~ ~r/\[api\] GET \/api\/v1\/stats 200 \d+ms request_id=\[FILTERED\]/
    assert log =~ ~r/\[api\] GET \/api\/v1\/digests\/2023 304 \d+ms request_id=\[FILTERED\]/
    refute log =~ "handed to Rails"
  end

  test "DB errors terminate natively in each stats controller",
       %{upstream: upstream} do
    Ecto.Adapters.SQL.Sandbox.checkin(Repo)

    for {controller, action, path} <- [
          {StatsController, :index, "/api/v1/stats"},
          {DigestsController, :closure_index, "/api/v1/digests"},
          {GeoController, :flights, "/api/v1/flights"}
        ] do
      conn =
        Plug.Test.conn(:get, path)
        |> Plug.Conn.put_req_header("accept", "application/json")
        |> DawarichWeb.Api.Respond.prepare()
        |> Plug.Conn.assign(:api_user, %{id: 1, timezone: nil})
        |> Plug.Conn.assign(:api_params, %{})
        |> Plug.Conn.assign(:api_tag, "api")
        |> Plug.Conn.put_private(:dawarich_raw_body, "")
        |> Plug.Conn.put_private(:dawarich_native_api, true)

      log =
        with_info_log(fn ->
          result = controller.call(conn, action)
          assert result.halted
          assert result.status == 500

          expected =
            if controller == DigestsController,
              do: %{"error" => "Digest request failed"},
              else: %{"error" => "internal_server_error"}

          assert Jason.decode!(result.resp_body) == expected
          no_upstream!(upstream)
        end)

      refute log =~ "handed to Rails"
    end
  end
end
