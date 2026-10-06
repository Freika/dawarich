defmodule DawarichWeb.A12f2BClosureTest do
  use ExUnit.Case, async: false
  import Dawarich.Test.RawHTTP
  alias Dawarich.{Repo, Redis}
  alias Dawarich.Photos.{Index, ProviderCache}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Dawarich.ApiEndpointCase.clear_transport_env()
    start_supervised!(hd(Redis.child_specs()))
    start_supervised!(hd(Redis.cache_child_specs()))

    [[id]] =
      Repo.query!(
        "INSERT INTO users (email, encrypted_password, settings, created_at, updated_at) VALUES ($1, '', '{}', NOW(), NOW()) RETURNING id",
        ["b-#{Ecto.UUID.generate()}@example.test"]
      ).rows

    user = %{id: id, timezone: "Etc/UTC", plan: 1, active_until: nil}

    on_exit(fn ->
      Redis.cache_command([
        "UNLINK",
        "dawarich/photoprism_preview_token_#{id}",
        "photos_#{id}_v2_2024-01-01_2024-01-02"
      ])
    end)

    {:ok, user: user}
  end

  @tag :a12f2_b_02
  test "Photo index mirrors configured Immich and PhotoPrism results errors time parsing and cache token writes",
       %{user: user} do
    photo = %{
      "Hash" => "a.b",
      "Type" => "image",
      "Lat" => 52.52,
      "Lng" => 13.405,
      "TakenAt" => "2024-01-01T12:00:00Z",
      "TakenAtLocal" => "2024-01-01T13:00:00Z",
      "OriginalName" => "synthetic.jpg",
      "Portrait" => true
    }

    {base, task} =
      provider([
        {"GET", "/api/v1/photos?", 200, Jason.encode!([photo]),
         [{"X-Preview-Token", "synthetic-preview"}]},
        {"GET", "/api/v1/photos?", 200, "[]", [{"X-Preview-Token", "synthetic-preview"}]}
      ])

    settings(user, %{"photoprism_url" => base, "photoprism_api_key" => "synthetic-key"})
    params = %{"start_date" => "2024-01-01", "end_date" => "2024-01-02"}
    assert {:ok, photos, []} = invoke(Index, :fetch, [user, params])
    assert [%{"id" => "a.b", "orientation" => "portrait", "source" => "photoprism"}] = photos
    assert invoke(ProviderCache, :token, [user.id]) == "synthetic-preview"
    assert photos == oracle("closure_photos_photoprism")
    requests = Task.await(task)

    assert Enum.all?(requests, fn {head, _} ->
             header(head, "authorization") == ["Bearer synthetic-key"]
           end)

    assert invoke(Index, :fetch, [user, params]) == {:ok, photos, []}
    assert {:ok, ttl} = Redis.cache_command(["TTL", "photos_#{user.id}_v2_2024-01-01_2024-01-02"])
    assert ttl in 1790..1800
    assert :ok = invoke(ProviderCache, :invalidate, [user.id])
    assert invoke(ProviderCache, :token, [user.id]) == nil
    settings(user, %{})
    assert {:unconfigured, nil} = invoke(Index, :fetch, [user, %{}])

    immich_photo = %{
      "id" => "asset.one",
      "type" => "IMAGE",
      "fileCreatedAt" => "2024-01-01T12:00:00Z",
      "localDateTime" => "2024-01-01T13:00:00",
      "originalFileName" => "synthetic.jpg",
      "exifInfo" => %{"latitude" => 52.52, "longitude" => 13.405, "orientation" => "6"}
    }

    {base, task} =
      provider([
        {"POST", "/api/search/metadata", 200,
         Jason.encode!(%{
           "assets" => %{
             "items" => [
               immich_photo,
               Map.put(immich_photo, "isArchived", true),
               Map.put(immich_photo, "type", "VIDEO")
             ]
           }
         }), []},
        {"POST", "/api/search/metadata", 200, Jason.encode!(%{"assets" => %{"items" => []}}), []}
      ])

    settings(user, %{
      "immich_url" => base,
      "immich_api_key" => "synthetic-key",
      "photoprism_url" => "http://127.0.0.1:1",
      "photoprism_api_key" => "synthetic-key"
    })

    assert {:ok, photos, ["photoprism"]} = Index.fetch(user, params)
    assert photos == oracle("closure_photos_immich")
    [{_, body}, {_, second}] = Task.await(task)
    assert Jason.decode!(body)["page"] == 1
    assert Jason.decode!(second)["page"] == 2
    assert Jason.decode!(body)["takenBefore"] == "2024-01-02T22:59:59Z"
    assert ProviderCache.get(ProviderCache.key(user.id, "2024-01-01", "2024-01-02")) == :miss
    {base, task} = provider([{"POST", "/api/search/metadata", 200, "invalid", []}])
    settings(user, %{"immich_url" => base, "immich_api_key" => "synthetic-key"})
    assert {:error, 502} = Index.fetch(user, params)
    Task.await(task)
  end

  @tag :a12f2_b_03
  test "Private thumbnails preserve arbitrary source IDs PhotoPrism tokens binary bytes and source failures",
       %{user: user} do
    ProviderCache.put_token(user.id, "synthetic-preview")
    image = <<255, 216, 0, 255, 217>>

    {base, task} =
      provider([{"GET", "/api/v1/t/a.%E9%9B%AA/synthetic-preview/tile_500", 200, image, []}])

    configured = %{"photoprism_url" => base, "photoprism_api_key" => "synthetic-key"}

    assert invoke(Dawarich.Photos.Thumbnail, :fetch, [configured, "photoprism", "a.雪", user.id]) ==
             {:ok, image}

    [{head, _}] = Task.await(task)
    assert header(head, "accept") == ["application/octet-stream"]

    for status <- [401, 403, 404, 503] do
      {base, task} =
        provider([{"GET", "/api/assets/a%2Fb/thumbnail?size=preview", status, "failed", []}])

      configured = %{"immich_url" => base, "immich_api_key" => "synthetic-key"}

      assert invoke(Dawarich.Photos.Thumbnail, :fetch, [configured, "immich", "a/b", user.id]) ==
               {:error, status}

      [{head, _}] = Task.await(task)
      assert header(head, "x-api-key") == ["synthetic-key"]
    end
  end

  @tag :a12f2_b_04
  test "Location suggestions retain Rails validation provider selection shared cache and limiter errors",
       %{user: user} do
    assert invoke(Dawarich.Locations.Suggestions, :run, [
             user,
             %{"q" => String.duplicate("x", 201)}
           ]) == {:ok, 400, %{"error" => "Search query too long (max 200 characters)"}}

    assert invoke(Dawarich.Locations.Suggestions, :run, [user, %{"q" => " "}]) ==
             {:ok, 200, %{"suggestions" => []}}

    {base, task} =
      provider([
        {"GET", "/api?", 200,
         Jason.encode!(%{
           "type" => "FeatureCollection",
           "features" => [feature("Café", 52.52, 13.405), feature("Duplicate", 52.5201, 13.405)]
         }), []}
      ])

    geocoder(base)

    assert {:ok, 200,
            %{
              "suggestions" => [
                %{"name" => "Café", "coordinates" => [52.52, 13.405], "type" => "Feature"}
              ]
            }} = result = invoke(Dawarich.Locations.Suggestions, :run, [user, %{"q" => " Café "}])

    [{head, _}] = Task.await(task)

    assert URI.decode_query(URI.parse(Enum.at(String.split(request_line(head)), 1)).query)["q"] ==
             "Café"

    assert invoke(Dawarich.Locations.Suggestions, :run, [user, %{"q" => "Café"}]) == result

    assert {:ok, 200, _} =
             invoke(Dawarich.Locations.Closure, :read, [
               user,
               %{"lat" => "52.52abc", "lon" => "13.405", "date_from" => "bad"}
             ])

    assert {:ok, 400, _} =
             invoke(Dawarich.Locations.Closure, :read, [user, %{"lat" => "91", "lon" => "0"}])

    config = Dawarich.Geocoding.Config.resolve(Repo)

    Redis.command([
      "SET",
      "geocoding:rate_limit:" <> Dawarich.Geocoding.RateLimiter.key(config),
      Integer.to_string(System.system_time(:microsecond) + 5_000_000),
      "PX",
      "10000"
    ])

    assert invoke(Dawarich.Locations.Suggestions, :run, [user, %{"q" => "Uncached"}]) ==
             {:ok, 200, %{"suggestions" => []}}
  end

  @tag :a12f2_b_05
  test "Nearby places preserve actor scope coordinate validation radius sort and formatted cache results",
       %{user: user} do
    assert {:ok, 400, _} = invoke(Dawarich.PlacesApi.Nearby, :run, [user, %{}])

    {base, task} =
      provider([
        {"GET", "/reverse?", 200,
         Jason.encode!(%{
           "type" => "FeatureCollection",
           "features" => [feature("Café", 52.52, 13.405)]
         }), []}
      ])

    geocoder(base)

    assert {:ok, 200, %{"places" => [%{"name" => "Café", "source" => "photon", "id" => nil}]}} =
             invoke(Dawarich.PlacesApi.Nearby, :run, [
               user,
               %{
                 "latitude" => "52.52abc",
                 "longitude" => "13.405",
                 "radius" => "0.5",
                 "limit" => "10"
               }
             ])

    [{head, _}] = Task.await(task)
    query = URI.decode_query(URI.parse(Enum.at(String.split(request_line(head)), 1)).query)
    assert query["radius"] == "0.5"
    assert query["distance_sort"] == "true"

    assert invoke(Dawarich.PlacesApi.Nearby, :run, [
             user,
             %{"latitude" => "0", "longitude" => "0"}
           ]) == {:ok, 200, %{"places" => []}}

    own = place(user.id, "Own", 52.52, 13.405)
    foreign = place(user.id + 1, "Foreign", 52.52, 13.405)

    assert [%{"id" => ^own}] =
             invoke(Dawarich.PlacesApi.Nearby, :saved, [user.id, 52.52, 13.405, 0.5, 10, ""])

    assert own != foreign
  end

  @tag :a12f2_b_06
  test "Place search and CRUD retain geocoder saved place dedup tags and refusal semantics", %{
    user: user
  } do
    assert {:ok, 400, _} = invoke(Dawarich.PlacesApi.Search, :run, [user, %{}])
    own = place(user.id, "Café", 52.52, 13.405)
    place(user.id + 1, "Café", 52.52, 13.405)

    {base, task} =
      provider([
        {"GET", "/api?", 200,
         Jason.encode!(%{
           "type" => "FeatureCollection",
           "features" => [
             feature(" café ", 52.52001, 13.405),
             feature("Café elsewhere", 52.523, 13.405)
           ]
         }), []}
      ])

    geocoder(base)

    assert {:ok, 200,
            %{
              "places" => [%{"id" => ^own}, %{"id" => nil, "name" => "Café elsewhere"}],
              "areas" => []
            }} =
             invoke(Dawarich.PlacesApi.Search, :run, [
               user,
               %{"lat" => "52.52", "lon" => "13.405", "q" => "Café"}
             ])

    Task.await(task)

    [[tag]] =
      Repo.query!(
        "INSERT INTO tags (user_id,name,created_at,updated_at) VALUES ($1,'Private',NOW(),NOW()) RETURNING id",
        [user.id]
      ).rows

    now = ~U[2026-10-06 12:00:00Z]

    assert {:ok, 201, term, []} =
             invoke(Dawarich.PlacesApi.Closure, :run, [
               :create,
               user,
               %{
                 "place" => %{
                   "name" => "Straße",
                   "latitude" => 52.52,
                   "longitude" => 13.405,
                   "tag_ids" => [tag],
                   "user_id" => user.id + 1
                 }
               },
               now
             ])

    object = term_map(term)
    assert object["name"] == "Straße"
    assert [%{"id" => ^tag}] = object["tags"]
    id = object["id"]

    assert {:ok, 200, term, []} =
             invoke(Dawarich.PlacesApi.Closure, :run, [
               :update,
               user,
               %{"id" => to_string(id), "place" => %{"tag_ids" => []}},
               now
             ])

    assert term_map(term)["tags"] == []

    assert {:ok, 404, _, []} =
             invoke(Dawarich.PlacesApi.Closure, :run, [
               :show,
               %{user | id: user.id + 1},
               %{"id" => to_string(id)},
               now
             ])

    assert :no_content =
             invoke(Dawarich.PlacesApi.Closure, :run, [
               :destroy,
               user,
               %{"id" => to_string(id)},
               now
             ])

    assert {:ok, 404, _, []} =
             invoke(Dawarich.PlacesApi.Closure, :run, [:show, user, %{"id" => to_string(id)}, now])
  end

  @tag :a12f2_b_07
  test "Immich enrichment preserves Pro access remote writes verification enqueue and partial failure outcomes",
       %{user: user} do
    assert {:ok, 200, %{"error" => "Immich URL is missing"}} =
             invoke(Dawarich.Photos.Enrichment, :run, [:scan, user, %{}, []])

    now = ~U[2026-10-06 12:00:00Z]
    assert Dawarich.Photos.Enrichment.pro?(%{user | plan: 0}, now)
    hosted = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")
    assert not Dawarich.Photos.Enrichment.pro?(%{user | plan: 0}, now)
    if hosted, do: System.put_env("SELF_HOSTED", hosted), else: System.delete_env("SELF_HOSTED")
    parent = self()

    {base, task} =
      provider([
        {"PUT", "/api/assets/one", 200, "{}", []},
        {"PUT", "/api/assets/two", 400, "{}", []}
      ])

    settings(user, %{"immich_url" => base, "immich_api_key" => "synthetic-key"})

    assets = [
      %{
        "immich_asset_id" => "one",
        "latitude" => 52.52,
        "longitude" => 13.405,
        "ignored" => "value"
      },
      %{"immich_asset_id" => "two", "latitude" => 0, "longitude" => 0}
    ]

    enqueue = fn id, submitted, url, at ->
      send(parent, {:verification, id, submitted, url, at})
      :ok
    end

    assert {:ok, 200,
            %{
              "enriched" => 0,
              "pending" => 1,
              "failed" => 1,
              "errors" => [%{"immich_asset_id" => "two"}]
            }} =
             invoke(Dawarich.Photos.Enrichment, :run, [
               :create,
               user,
               %{"assets" => assets},
               [enqueue: enqueue, now: ~U[2026-10-06 12:00:00Z]]
             ])

    assert_receive {:verification, notification, [%{"immich_asset_id" => "one"} = submitted],
                    ^base, ~U[2026-10-06 12:00:10Z]}

    refute Map.has_key?(submitted, "ignored")

    assert [["Checking Immich location updates"]] =
             Repo.query!("SELECT title FROM notifications WHERE id=$1 AND user_id=$2", [
               notification,
               user.id
             ]).rows

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM phoenix.notification_events WHERE notification_id=$1",
               [notification]
             ).rows

    [{head, body}, _] = Task.await(task)
    assert header(head, "x-api-key") == ["synthetic-key"]
    assert Jason.decode!(body) == %{"latitude" => 52.52, "longitude" => 13.405}
    {base, task} = provider([{"PUT", "/api/assets/one", 200, "{}", []}])
    settings(user, %{"immich_url" => base, "immich_api_key" => "synthetic-key"})

    assert invoke(Dawarich.Photos.Enrichment, :run, [
             :create,
             user,
             %{"assets" => [hd(assets)]},
             [enqueue: fn _, _, _, _ -> raise "after accepted PUT" end]
           ]) == {:error, 500}

    Task.await(task)

    asset = %{
      "id" => "scan.one",
      "type" => "IMAGE",
      "fileCreatedAt" => "2024-01-01T12:00:00Z",
      "originalFileName" => "synthetic.jpg",
      "exifInfo" => %{}
    }

    {base_scan, scan_task} =
      provider([
        {"POST", "/api/search/metadata", 200, Jason.encode!(%{"assets" => %{"items" => [asset]}}),
         []},
        {"POST", "/api/search/metadata", 200, Jason.encode!(%{"assets" => %{"items" => []}}), []}
      ])

    settings(user, %{"immich_url" => base_scan, "immich_api_key" => "synthetic-key"})
    ts = DateTime.to_unix(~U[2024-01-01 12:00:00Z])

    for {stamp, lat, lon} <- [{ts - 100, 52.0, 13.0}, {ts + 100, 52.02, 13.02}] do
      Repo.query!(
        "INSERT INTO points (user_id,timestamp,lonlat,created_at,updated_at) VALUES ($1,$2,ST_SetSRID(ST_MakePoint($4::float8,$3::float8),4326),NOW(),NOW())",
        [user.id, stamp, lat, lon]
      )
    end

    assert {:ok, 200,
            %{
              "matches" => [
                %{
                  "match_method" => "interpolated",
                  "time_delta_seconds" => 100,
                  "immich_asset_id" => "scan.one"
                }
              ],
              "total_matched" => 1
            }} = Dawarich.Photos.Enrichment.run(:scan, user, %{})

    Task.await(scan_task)
    settings(user, %{"immich_url" => base, "immich_api_key" => "synthetic-key"})

    assert invoke(Dawarich.Photos.Enrichment, :run, [
             :create,
             user,
             %{"assets" => [hd(assets)]},
             []
           ]) == {:error, :verification_unavailable}
  end

  defp oracle(name) do
    fixture = "test/fixtures/a12f2b/closure.json" |> File.read!() |> Jason.decode!()
    kase = Enum.find(fixture["locations_photos"], &(&1["name"] == name))
    Jason.decode!(kase["response"]["body"])
  end

  defp term_map({:object, pairs}), do: Map.new(pairs, fn {k, v} -> {k, term_map(v)} end)
  defp term_map(list) when is_list(list), do: Enum.map(list, &term_map/1)
  defp term_map(value), do: value

  defp place(owner, name, lat, lon) do
    [[id]] =
      Repo.query!(
        "INSERT INTO places (user_id,name,latitude,longitude,lonlat,source,created_at,updated_at) VALUES ($1,$2,$3::float8,$4::float8,ST_SetSRID(ST_MakePoint($4::float8,$3::float8),4326)::geography,0,NOW(),NOW()) RETURNING id",
        [owner, name, lat, lon]
      ).rows

    id
  end

  defp feature(name, lat, lon),
    do: %{
      "type" => "Feature",
      "geometry" => %{"type" => "Point", "coordinates" => [lon, lat]},
      "properties" => %{"name" => name, "city" => "Berlin", "country" => "Germany"}
    }

  defp geocoder(base) do
    previous_http = Application.fetch_env!(:dawarich, :geocoding_http)
    Application.put_env(:dawarich, :geocoding_http, Dawarich.Geocoding.Http)
    on_exit(fn -> Application.put_env(:dawarich, :geocoding_http, previous_http) end)

    vars =
      ~w(PHOTON_API_HOST PHOTON_API_KEY PHOTON_API_USE_HTTPS REVERSE_GEOCODING_RPS GEOAPIFY_API_KEY NOMINATIM_API_HOST LOCATIONIQ_API_KEY)

    saved = Map.new(vars, &{&1, System.get_env(&1)})
    Enum.each(vars, &System.delete_env/1)

    System.put_env(
      "PHOTON_API_HOST",
      URI.parse(base).host <> ":" <> Integer.to_string(URI.parse(base).port)
    )

    System.put_env("PHOTON_API_USE_HTTPS", "false")
    System.put_env("REVERSE_GEOCODING_RPS", "10")
    Redis.command(["UNLINK", "geocoding:rate_limit:photon:127.0.0.1"])
    on_exit(fn -> Redis.command(["UNLINK", "geocoding:rate_limit:photon:127.0.0.1"]) end)

    on_exit(fn ->
      Enum.each(saved, fn {k, v} -> if v, do: System.put_env(k, v), else: System.delete_env(k) end)
    end)
  end

  defp invoke(module, function, args) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, length(args)),
      do: apply(module, function, args),
      else: {:error, :not_implemented}
  end

  defp settings(user, values),
    do: Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [user.id, values])

  defp provider(responses) do
    server = listen()

    task =
      Task.async(fn ->
        Enum.map(responses, fn {method, path, status, body, headers} ->
          socket = accept(server)
          {head, rest} = read_head(socket)
          assert String.starts_with?(request_line(head), "#{method} #{path}")
          length = head |> header("content-length") |> List.first() || "0"
          sent = read_at_least(socket, rest, String.to_integer(length))

          headers = [{"Content-Type", "application/json"} | headers]

          reply(socket, [
            "HTTP/1.1 #{status} OK\r\nconnection: close\r\ncontent-length: #{byte_size(body)}\r\n",
            Enum.map(headers, fn {k, v} -> "#{k}: #{v}\r\n" end),
            "\r\n",
            body
          ])

          :gen_tcp.close(socket)
          {head, sent}
        end)
      end)

    {"http://127.0.0.1:#{server.port}", task}
  end
end
