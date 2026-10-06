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
