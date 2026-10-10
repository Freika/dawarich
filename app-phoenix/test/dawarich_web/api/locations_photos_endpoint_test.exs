defmodule DawarichWeb.Api.LocationsPhotosEndpointTest do
  use Dawarich.ApiEndpointCase

  alias DawarichWeb.Api.{LocationsController, PhotosController}

  @moduletag :capture_log

  @key "phoenix-a4g3-key-endpoint"
  @id "3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b"
  @thumb "/api/v1/photos/3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b/thumbnail"
  @image <<0xFF, 0xD8, 0xFF, 0xE0, "phoenix-a4g3", 0x00, 0xFF, 0xD9>>
  @preview "GET /api/assets/3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b/thumbnail?size=preview HTTP/1.1"

  defp bearer(key \\ @key),
    do: [{"Authorization", "Bearer #{key}"}, {"Accept", "application/json"}]

  defp owner!(key \\ @key, settings \\ %{}),
    do: user!(%{api_key: key, settings: Map.merge(%{"timezone" => "UTC"}, settings)})

  defp immich_settings(base),
    do: %{"immich_url" => base, "immich_api_key" => "phoenix-a4g3-immich-key"}

  defp answer(status \\ 200, body \\ @image),
    do:
      "HTTP/1.1 #{status} X\r\nconnection: close\r\ncontent-length: #{byte_size(body)}\r\n\r\n" <>
        body

  defp immich(replies) do
    server = listen()

    {"http://127.0.0.1:#{server.port}",
     Task.async(fn -> Enum.map(replies, &serve(server, &1)) end)}
  end

  defp serve(server, reply) do
    socket = accept(server)
    {head, _rest} = read_head(socket)
    reply(socket, reply)
    :gen_tcp.close(socket)
    request_line(head)
  end

  defp stall(server, attempts) do
    for _attempt <- 1..attempts do
      socket = accept(server)
      read_head(socket)
      {:error, :closed} = :gen_tcp.recv(socket, 0, 5_000)
    end
  end

  test "photo scan equal timestamps keep point ID order across query plans" do
    photo = %{
      "id" => "tied-photo",
      "fileCreatedAt" => "2026-10-03T10:00:00Z",
      "originalFileName" => "synthetic.jpg"
    }

    json_reply = fn items ->
      body = Jason.encode!(%{"assets" => %{"items" => items}})

      "HTTP/1.1 200 OK\r\nconnection: close\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\n\r\n#{body}"
    end

    {base, provider} =
      immich([json_reply.([photo]), json_reply.([]), json_reply.([photo]), json_reply.([])])

    user_id = owner!(@key, immich_settings(base))
    user = Dawarich.Accounts.get(user_id)

    for {id, lat} <- [{919_641, 51.3398}, {919_640, 51.3397}] do
      Dawarich.Test.FrameSeeds.point!(user.id, id, DateTime.to_unix(~U[2026-10-03 10:00:00Z]))

      Repo.query!(
        "UPDATE points SET lonlat=ST_SetSRID(ST_MakePoint(12.3731,$1),4326)::geography WHERE id=$2",
        [lat, id]
      )
    end

    for {seq, index} <- [{"on", "off"}, {"off", "on"}] do
      Repo.query!("SET LOCAL enable_seqscan = #{seq}")
      Repo.query!("SET LOCAL enable_indexscan = #{index}")
      Repo.query!("SET LOCAL enable_indexonlyscan = off")
      Repo.query!("SET LOCAL enable_bitmapscan = off")

      assert {:ok, 200, %{"matches" => [match]}} =
               Dawarich.Photos.Enrichment.run(:scan, user, %{})

      assert match["latitude"] == 51.3398
      assert match["longitude"] == 12.3731
      assert match["match_method"] == "nearest"
    end

    assert length(Task.await(provider)) == 4
  end

  test "Phoenix answers /locations and both thumbnail routes of a self-hosted user", %{
    port: port,
    upstream: upstream
  } do
    {base, immich} = immich([answer(), answer()])
    owner!(@key, immich_settings(base))

    assert {200, headers, body} =
             port
             |> request("/api/v1/locations?lat=52.52&lon=13.405", bearer())
             |> read_response()

    assert {values(headers, "content-type"), body} ==
             {["application/json; charset=utf-8"],
              ~s({"query":null,"locations":[],"total_locations":0,"search_metadata":{}})}

    for target <- ["#{@thumb}?source=immich", "#{@thumb}.jpg?source=immich&api_key=#{@key}"] do
      assert {200, headers, @image} = port |> request(target, bearer()) |> read_response(), target

      assert {values(headers, "content-type"), values(headers, "content-disposition"),
              values(headers, "content-transfer-encoding"), values(headers, "cache-control")} ==
               {["image/jpeg"], ["inline"], ["binary"], ["max-age=1800, private"]},
             target
    end

    assert Task.await(immich) == [@preview, @preview]
    no_upstream!(upstream)
  end

  test "Vary: Accept on the bare thumbnail with a JSON Accept, none for .jpg or ?format=jpg whatever the Accept; the 304 keeps Content-Disposition",
       %{port: port} do
    {base, immich} = immich([answer(), answer(), answer(), answer()])
    owner!(@key, immich_settings(base))
    any = [{"Authorization", "Bearer #{@key}"}, {"Accept", "*/*"}]

    assert {200, bare, _} =
             port |> request("#{@thumb}?source=immich", bearer()) |> read_response()

    assert values(bare, "vary") == ["Accept"]

    for target <- ["#{@thumb}.jpg?source=immich", "#{@thumb}?source=immich&format=jpg"] do
      assert {200, headers, _} = port |> request(target, any) |> read_response(), target
      assert values(headers, "vary") == [], target
    end

    [etag] = values(bare, "etag")

    assert {304, again, ""} =
             port
             |> request("#{@thumb}?source=immich", bearer() ++ [{"If-None-Match", etag}])
             |> read_response()

    assert {values(again, "content-disposition"), values(again, "content-transfer-encoding"),
            values(again, "content-type"), values(again, "etag")} ==
             {["inline"], ["binary"], [], [etag]}

    Task.await(immich)
  end

  test "/locations: Rails' two 400s and the edge of the range; no key 401; pending 402; inactive and expired users read",
       %{port: port} do
    owner!()

    assert {400, missing, ~s|{"error":"Coordinates (lat, lon) are required"}|} =
             port |> request("/api/v1/locations?lat=52", bearer()) |> read_response()

    assert values(missing, "cache-control") == ["no-cache"]

    assert {400, _,
            ~s({"error":"Invalid coordinates: lat must be -90..90, lon must be -180..180"})} =
             port |> request("/api/v1/locations?lat=90.5&lon=13", bearer()) |> read_response()

    assert {200, _, _} =
             port |> request("/api/v1/locations?lat=90&lon=-180", bearer()) |> read_response()

    assert {401, _, ""} = port |> request("/api/v1/locations?lat=1&lon=1", []) |> read_response()

    user!(%{api_key: "phoenix-a4g3-key-pending", status: 3})

    assert {402, _,
            ~s({"error":"payment_required","message":"Complete your subscription to continue.","resume_url":null})} =
             port
             |> request("#{@thumb}?source=immich", bearer("phoenix-a4g3-key-pending"))
             |> read_response()

    user!(%{api_key: "phoenix-a4g3-key-inactive", status: 0})
    user!(%{api_key: "phoenix-a4g3-key-expired", active_until: ~N[2001-01-01 00:00:00]})

    for key <- ~w(phoenix-a4g3-key-inactive phoenix-a4g3-key-expired),
        do:
          assert(
            {200, _, _} =
              port |> request("/api/v1/locations?lat=1&lon=1", bearer(key)) |> read_response(),
            key
          )
  end

  test "thumbnail gates: Rails' 401 with the capitalized source; upstream error statuses and a timeout map to Rails' JSON",
       %{port: port} do
    owner!("phoenix-a4g3-key-bare", %{})

    assert {401, _, ~s({"error":"Immich integration not configured"})} =
             port
             |> request("#{@thumb}?source=immich", bearer("phoenix-a4g3-key-bare"))
             |> read_response()

    assert {401, _, ~s({"error":" integration not configured"})} =
             port |> request(@thumb, bearer("phoenix-a4g3-key-bare")) |> read_response()

    {base, immich} = immich([answer(404, "{}"), answer(503, "down")])
    owner!(@key, immich_settings(base))

    assert {401, _, ~s({"error":"Flickr integration not configured"})} =
             port |> request("#{@thumb}?source=fLICKR", bearer()) |> read_response()

    assert {404, missing, ~s({"error":"Failed to fetch thumbnail"})} =
             port |> request("#{@thumb}?source=immich", bearer()) |> read_response()

    assert {values(missing, "cache-control"), values(missing, "etag")} == {["no-cache"], []}

    assert {503, _, ~s({"error":"Failed to fetch thumbnail"})} =
             port |> request("#{@thumb}?source=immich", bearer()) |> read_response()

    Task.await(immich)

    put_photo_source_timeout(300)
    stalled = listen()
    owner!("phoenix-a4g3-key-stalled", immich_settings("http://127.0.0.1:#{stalled.port}"))
    waits = Task.async(fn -> stall(stalled, 2) end)

    assert {502, _, ~s({"error":"Failed to fetch photos"})} =
             port
             |> request("#{@thumb}?source=immich", bearer("phoenix-a4g3-key-stalled"))
             |> read_response()

    Task.await(waits)
    no_upstream!(stalled)
  end

  test "inputs Phoenix does not own go to Puma, before or after the upstream fetch", %{
    port: port,
    upstream: upstream
  } do
    {base, immich} = immich([answer(403, ~s({"message":"asset.view"})), answer(302, "")])

    owner!(
      @key,
      Map.merge(immich_settings(base), %{
        "photoprism_url" => "http://photoprism.invalid",
        "photoprism_api_key" => "k"
      })
    )

    user!(%{api_key: "phoenix-a4g3-key-zone", settings: %{"timezone" => "europe/berlin"}})

    for {target, headers} <- [
          {"/api/v1/locations?lat=52.52abc&lon=13.405", bearer()},
          {"/api/v1/locations?lat=52.52&lon=13.405&limit=-1", bearer()},
          {"/api/v1/locations?lat=52.52&lon=13.405&date_from=Nov%2015", bearer()},
          {"/api/v1/locations?lat=52.52&lon=13.405", bearer("phoenix-a4g3-key-zone")},
          {"#{@thumb}?source=photoprism", bearer()},
          {"#{@thumb}?source=%C3%BC", bearer()},
          {"#{@thumb}?source=immich", bearer()},
          {"#{@thumb}?source=immich", bearer()}
        ] do
      client = request(port, target, headers)
      assert puma(upstream) == "GET #{target} HTTP/1.1", target
      assert {200, _, "rails"} = read_response(client)
    end

    assert Task.await(immich) == [@preview, @preview]
  end

  test "NULL and JSON null settings use the default unconfigured photo response",
       %{port: port, upstream: upstream} do
    user!(%{api_key: "phoenix-a4g3-key-sql-null", settings: nil})
    json_null = user!(%{api_key: "phoenix-a4g3-key-json-null"})
    Repo.query!("UPDATE users SET settings = 'null'::jsonb WHERE id = $1", [json_null])

    for key <- ~w(phoenix-a4g3-key-sql-null phoenix-a4g3-key-json-null) do
      proxy = Task.async(fn -> puma(upstream) end)

      try do
        client = request(port, "#{@thumb}?source=immich", bearer(key))
        assert {401, _, body} = read_response(client)
        assert Jason.decode!(body) == %{"error" => "Immich integration not configured"}
        refute Task.yield(proxy, 0)
      after
        Task.shutdown(proxy, :brutal_kill)
      end
    end
  end

  test "Cloud legacy reads, the kill switch, HEAD, other suffixes and other ids reach Puma before auth",
       %{port: port, upstream: upstream} do
    owner!()

    for {method, target, env} <- [
          {"GET", "/api/v1/locations?lat=1&lon=1", {"SELF_HOSTED", "false"}},
          {"GET", "#{@thumb}?source=immich", {"DAWARICH_RAILS_SLICES", "api_locations_photos"}},
          {"HEAD", "#{@thumb}.jpg?source=immich", nil},
          {"GET", "#{@thumb}.jpeg?source=immich", nil},
          {"GET", "/api/v1/locations.json?lat=1&lon=1", nil},
          {"GET", "/api/v1/photos/a.b/thumbnail?source=immich", nil},
          {"GET", "/api/v1/photos/#{String.duplicate("a", 129)}/thumbnail", nil},
          {"GET", "/api/v1/photos?start_date=2024-01-01&end_date=2024-01-02",
           {"DAWARICH_RAILS_SLICES", "api_locations_photos"}},
          {"GET", "/api/v1/locations/suggestions?q=Berlin",
           {"DAWARICH_RAILS_SLICES", "api_locations_photos"}},
          {"POST", "/api/v1/immich/enrich/scan",
           {"DAWARICH_RAILS_SLICES", "api_locations_photos"}},
          {"POST", "/api/v1/immich/enrich", {"DAWARICH_RAILS_SLICES", "api_locations_photos"}}
        ] do
      Enum.each(~w(SELF_HOSTED DAWARICH_RAILS_SLICES), &System.delete_env/1)
      with {name, value} <- env, do: System.put_env(name, value)
      client = request(port, target, [{"Accept", "application/json"}], method)

      assert puma(upstream, if(method == "HEAD", do: "", else: "rails")) ==
               "#{method} #{target} HTTP/1.1",
             target

      assert {200, _, _} = read_response(client, method: method)
    end

    System.delete_env("DAWARICH_RAILS_SLICES")

    for hosted <- ["true", "false"] do
      System.put_env("SELF_HOSTED", hosted)

      for {method, target} <- [
            {"GET", "/api/v1/photos?start_date=2024-01-01&end_date=2024-01-02"},
            {"GET", "/api/v1/locations/suggestions?q=Berlin"},
            {"POST", "/api/v1/immich/enrich/scan"},
            {"POST", "/api/v1/immich/enrich"}
          ] do
        assert {401, headers, ""} =
                 port
                 |> request(target, [{"Accept", "application/json"}], method)
                 |> read_response()

        assert values(headers, "x-dawarich-response") == ["Hey, I'm alive!"]
      end
    end

    no_upstream!(upstream)
  end

  @tag :review_privacy
  test "coordinate privacy checks inspect message payloads even when timestamps resemble coordinates" do
    clean = "16:37:52.529 [info] [api] GET /api/v1/locations 200 1ms\n"
    refute logged_messages(clean) =~ "52.52"
    leaked = "16:37:00.001 [info] [api] lat=52.52 lon=13.405\n"
    assert logged_messages(leaked) =~ "52.52"
    assert logged_messages(leaked) =~ "13.405"
  end

  defp logged_messages(log),
    do:
      String.replace(
        log,
        ~r/^.*?\[(?:debug|info|notice|warning|error|critical|alert|emergency)\]\s*/m,
        ""
      )

  test "answered lines carry the final status; hand-off reasons carry no coordinates, URLs or keys",
       %{port: port, upstream: upstream} do
    {base, immich} = immich([answer(302, "")])
    owner!(@key, immich_settings(base))

    log =
      with_info_log(fn ->
        assert {200, _, _} =
                 port
                 |> request("/api/v1/locations?lat=52.52&lon=13.405", bearer())
                 |> read_response()

        for target <- ["/api/v1/locations?lat=52.52abc&lon=13.405", "#{@thumb}?source=immich"] do
          client = request(port, target, bearer())
          assert puma(upstream) == "GET #{target} HTTP/1.1"
          assert {200, _, "rails"} = read_response(client)
        end
      end)

    Task.await(immich)
    assert log =~ ~r/\[api\] GET \/api\/v1\/locations 200 \d+ms request_id=[0-9a-f-]{36}/
    assert log =~ "[api] /api/v1/locations handed to Rails: coordinate parameter shape"
    assert log =~ "[api] #{@thumb} handed to Rails: photo source answered 302"
    messages = logged_messages(log)
    refute messages =~ "52.52"
    refute messages =~ "13.405"
    refute messages =~ base
    refute messages =~ "phoenix-a4g3-immich-key"
  end

  test "a DB error raised while reading hands off to Rails instead of crashing, in both controllers",
       %{upstream: upstream} do
    Ecto.Adapters.SQL.Sandbox.checkin(Repo)

    for {controller, action, path, params, path_params} <- [
          {LocationsController, :index, "/api/v1/locations",
           %{"lat" => "52.52", "lon" => "13.405"}, %{}},
          {PhotosController, :thumbnail, @thumb, %{"source" => "immich"}, %{"id" => @id}}
        ] do
      conn =
        Plug.Test.conn(:get, path)
        |> Map.put(:path_params, path_params)
        |> Plug.Conn.assign(:api_user, %{id: 1, timezone: nil})
        |> Plug.Conn.assign(:api_params, params)
        |> Plug.Conn.assign(:api_tag, "api")
        |> Plug.Conn.put_private(:dawarich_raw_body, "")

      proxied = Task.async(fn -> puma(upstream) end)

      log =
        with_info_log(fn ->
          assert controller.call(conn, action).halted
          assert Task.await(proxied) == "GET #{path} HTTP/1.1"
        end)

      assert log =~ "[api] #{path} handed to Rails: DBConnection.OwnershipError", path
    end
  end
end
