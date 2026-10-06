defmodule DawarichWeb.A12f3bS02Test do
  use Dawarich.ApiEndpointCase
  alias Dawarich.{RailsCookies, RailsSecret, SharedLinks}
  alias Dawarich.Photos.ProviderCache
  alias Dawarich.SharedApi.Closure
  alias DawarichWeb.SharedLinkCookie

  @moduletag :capture_log
  @moduletag api_now: ~U[2026-10-06 12:00:00Z]
  @image <<255, 216, 0, 255, 217>>
  @now ~U[2026-10-06 12:00:00Z]

  defmodule Provider do
    import Plug.Conn
    def init(state), do: state

    def call(conn, state) do
      {:ok, body, conn} = read_body(conn)
      conn = fetch_query_params(conn)

      request = %{
        path: conn.request_path,
        query: conn.query_params,
        body: body,
        headers: conn.req_headers
      }

      mode =
        Agent.get_and_update(state, fn s -> {s, update_in(s.requests, &(&1 ++ [request]))} end)

      cond do
        mode.failure == :timeout ->
          send(mode.parent, {:held_provider, self()})

          receive do
            :release -> send_resp(conn, 503, "")
          end

        is_integer(mode.failure) ->
          send_resp(conn, mode.failure, "")

        conn.request_path == "/api/search/metadata" ->
          items = if Jason.decode!(body)["page"] == 1, do: mode.immich, else: []

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{assets: %{items: items}}))

        conn.request_path == "/api/v1/photos" ->
          items = if conn.query_params["offset"], do: [], else: mode.prism

          conn
          |> put_resp_header("x-preview-token", mode.token)
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(items))

        true ->
          conn |> put_resp_content_type("image/jpeg") |> send_resp(200, <<255, 216, 0, 255, 217>>)
      end
    end
  end

  setup do
    previous = Map.take(System.get_env(), ~w(DAWARICH_RAILS SELF_HOSTED))
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true"})

    on_exit(fn ->
      Enum.each(~w(DAWARICH_RAILS SELF_HOSTED), &System.delete_env/1)
      System.put_env(previous)
    end)

    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

    state =
      start_supervised!(
        {Agent,
         fn ->
           %{
             immich: [],
             prism: [],
             failure: nil,
             token: "owner-preview",
             requests: [],
             parent: self()
           }
         end}
      )

    provider =
      start_supervised!({Bandit, plug: {Provider, state}, ip: {127, 0, 0, 1}, port: 0},
        id: :provider
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(provider)
    url = "http://127.0.0.1:#{port}"

    owner =
      user!(%{
        settings: %{
          "timezone" => "Europe/Berlin",
          "immich_url" => url,
          "immich_api_key" => "synthetic-owner"
        }
      })

    foreign =
      user!(%{
        settings: %{
          "timezone" => "UTC",
          "immich_url" => url,
          "immich_api_key" => "synthetic-foreign"
        }
      })

    trip = resource!("trips", owner)
    track = resource!("tracks", owner)
    other_trip = resource!("trips", foreign)
    other_track = resource!("tracks", foreign)
    zone!(owner)

    on_exit(fn ->
      ProviderCache.invalidate(owner)
      ProviderCache.invalidate(foreign)
    end)

    %{
      owner: owner,
      foreign: foreign,
      trip: trip,
      track: track,
      other_trip: other_trip,
      other_track: other_track,
      state: state,
      url: url,
      effects: effects()
    }
  end

  @tag a12f3b_case: "S02a"
  test "shared photos apply resource scope privacy and provider failures", c do
    assets =
      [asset("private", 52, 13), Map.delete(asset("unlocated"), "exifInfo")] ++
        Enum.map(0..100, &asset("public-#{&1}"))

    configure(c, assets)

    for {type, resource, size} <- [
          {0, c.trip, 100},
          {1, c.track, 100},
          {2, nil, 100},
          {3, nil, 0}
        ] do
      link = link!(c.owner, type, resource)
      {200, headers, body} = response(c, link, "photos?start_date=1970-01-01&end_date=2099-01-01")
      assert length(Jason.decode!(body)) == size
      assert {"cache-control", "max-age=60, public"} in headers
      assert {:ok, ids} = ProviderCache.get(Closure.photo_ids_key(SharedLinks.active(link, @now)))
      assert map_size(ids) == if(type == 0, do: 101, else: size)
      assert {status, _, image} = response(c, link, "photos/public-100/thumbnail?source=immich")
      assert status == if(type == 0, do: 200, else: 404)
      assert image == if(type == 0, do: @image, else: "")

      for id <- ~w(private unlocated foreign) do
        assert {404, _, ""} = response(c, link, "photos/#{id}/thumbnail?source=immich")
      end

      assert {200, _, ""} = response(c, link, "photos", [], "HEAD")

      assert {status, _, ""} =
               response(c, link, "photos/public-0/thumbnail?source=immich", [], "HEAD")

      assert status == if(type == 3, do: 404, else: 200)
      before_disabled = length(requests(c))
      set!(link, "settings", %{"show_photos" => false})
      assert {200, _, "[]"} = response(c, link, "photos")
      assert length(requests(c)) == before_disabled
      assert {404, _, ""} = response(c, link, "photos/public-0/thumbnail?source=immich")
      set!(link, "settings", %{"show_photos" => "true"})
      assert {200, _, "[]"} = response(c, link, "photos")
    end

    searches =
      requests(c)
      |> Enum.filter(&(&1.path == "/api/search/metadata"))
      |> Enum.map(&Jason.decode!(&1.body))

    assert Enum.all?(
             searches,
             &(&1["takenAfter"] in ["2026-03-29T00:00:00Z", "2026-03-28T23:00:00Z"])
           )

    assert Enum.all?(
             searches,
             &(&1["takenBefore"] in ["2026-03-29T01:00:00Z", "2026-03-29T21:59:59Z"])
           )

    link = link!(c.owner, 0, c.trip)
    set!(link, "magic_phrase", "synthetic-phrase")
    assert {401, _, ~s({"error":"unauthorized"})} = response(c, link, "photos")
    assert {200, headers, _} = response(c, link, "photos", cookie(link, "synthetic-phrase"))
    assert {"cache-control", "max-age=0, private, must-revalidate"} in headers
    set!(link, "magic_phrase", "rotated")

    assert {401, _, _} =
             response(
               c,
               link,
               "photos/public-0/thumbnail?source=immich",
               cookie(link, "synthetic-phrase")
             )

    set!(link, "magic_phrase", nil)

    for column <- ~w(expires_at revoked_at) do
      set!(link, column, DateTime.to_naive(@now))
      assert {404, _, ~s({"error":"not_found"})} = response(c, link, "photos")

      assert {404, _, ~s({"error":"not_found"})} =
               response(c, link, "photos/public-0/thumbnail?source=immich")

      set!(link, column, nil)
    end

    for variant <- ~w(strings missing_exif missing_time missing_type timeout) do
      photos = [
        asset("unlocated") |> Map.delete("exifInfo"),
        asset("private", 52, 13),
        asset("public-0"),
        asset("public-1")
      ]

      photos =
        case variant do
          "strings" ->
            Enum.map(
              photos,
              &update_in(&1["exifInfo"], fn exif ->
                if exif, do: Map.new(exif, fn {k, v} -> {k, to_string(v)} end)
              end)
            )

          "missing_exif" ->
            List.update_at(photos, 3, &Map.delete(&1, "exifInfo"))

          "missing_time" ->
            List.update_at(photos, 3, &Map.delete(&1, "fileCreatedAt"))

          "missing_type" ->
            List.update_at(photos, 3, &Map.delete(&1, "type"))

          _ ->
            photos
        end

      configure(c, photos, if(variant == "timeout", do: 503))
      {200, _, body} = response(c, link, "photos")
      oracle = Enum.find(source(), &(&1["name"] == "s02_#{variant}"))["response"]

      assert Jason.decode!(body) ==
               Jason.decode!(oracle["body"])
               |> Enum.map(
                 &Map.update!(&1, "thumbnail_url", fn url ->
                   String.replace(url, "a4951000-0000-4000-8000-000000000001", link)
                 end)
               )
    end

    configure(c, [asset("public-0")])
    link = link!(c.owner, 1, c.track)
    assert {200, _, @image} = response(c, link, "photos/public-0/thumbnail?source=immich")
    old_key = Closure.photo_ids_key(SharedLinks.active(link, @now))
    Repo.query!("UPDATE tags SET privacy_radius_meters=1000000 WHERE user_id=$1", [c.owner])
    new_key = Closure.photo_ids_key(SharedLinks.active(link, @now))
    refute old_key == new_key
    assert {404, _, ""} = response(c, link, "photos/public-0/thumbnail?source=immich")
    assert {:ok, old_ids} = ProviderCache.get(old_key)
    assert old_ids["immich:public-0"]
    Dawarich.Redis.cache_command(["UNLINK", old_key, new_key])
    assert commands() == []

    assert Repo.query!("SELECT view_count,last_accessed_at FROM shared_links").rows
           |> Enum.all?(&(&1 == [0, nil]))

    no_upstream!(c.upstream)
    assert effects() == c.effects
  end

  @tag a12f3b_case: "S02b"
  test "shared photo failure never borrows owner credentials outside scope", c do
    assets = [
      asset("private", 52, 13),
      asset("foreign-window") |> Map.put("fileCreatedAt", "2020-01-01T00:00:00Z"),
      asset("public-0")
    ]

    configure(c, assets)

    for {type, resource} <- [{0, c.other_trip}, {1, c.other_track}, {0, -1}, {1, -1}, {3, nil}] do
      link = link!(c.owner, type, resource)
      assert {200, _, "[]"} = response(c, link, "photos")
      assert {404, _, ""} = response(c, link, "photos/public-0/thumbnail?source=immich")
    end

    assert requests(c) == []

    link = link!(c.owner, 1, c.track)

    for id <- ~w(private foreign-window foreign) do
      assert {404, _, ""} = response(c, link, "photos/#{id}/thumbnail?source=immich")
    end

    assert Enum.all?(requests(c), &(&1.path == "/api/search/metadata"))
    assert {404, _, ""} = response(c, link, "photos/public-0/thumbnail?source=photoprism")
    assert {200, _, @image} = response(c, link, "photos/public-0/thumbnail?source=immich")

    for status <- [403, 404, 503] do
      Agent.update(c.state, &%{&1 | failure: status})
      assert {404, _, ""} = response(c, link, "photos/public-0/thumbnail?source=immich")
    end

    previous_timeout = Application.fetch_env(:dawarich, :photo_source_timeout)
    put_photo_source_timeout(50)
    parent = self()
    Agent.update(c.state, &%{&1 | failure: :timeout, parent: parent})
    assert {404, _, ""} = response(c, link, "photos/public-0/thumbnail?source=immich")
    release_timeouts()
    configure(c, [], :timeout)
    assert {200, _, "[]"} = response(c, link, "photos")
    release_timeouts()

    case previous_timeout do
      {:ok, value} -> Application.put_env(:dawarich, :photo_source_timeout, value)
      :error -> Application.delete_env(:dawarich, :photo_source_timeout)
    end

    assert Enum.all?(requests(c), fn r ->
             values(r.headers, "x-api-key") == ["synthetic-owner"]
           end)

    refute Enum.any?(requests(c), fn r ->
             values(r.headers, "x-api-key") == ["synthetic-foreign"]
           end)

    Repo.query!("UPDATE users SET settings=$1 WHERE id=$2", [
      %{
        "timezone" => "UTC",
        "photoprism_url" => c.url,
        "photoprism_api_key" => "synthetic-owner-prism"
      },
      c.owner
    ])

    ProviderCache.put_token(c.foreign, "foreign-preview")
    configure(c, [])

    Agent.update(
      c.state,
      &%{
        &1
        | prism: [
            prism("private", "52", "13"),
            Map.drop(prism("unlocated", "52", "13"), ~w(Lat Lng)),
            prism("public-0", "52.5", "13.4"),
            prism("public-1", "52.5", "13.4")
          ]
      }
    )

    link = link!(c.owner, 0, c.trip)
    assert {404, _, ""} = response(c, link, "photos/private/thumbnail?source=photoprism")
    {200, _, body} = response(c, link, "photos")
    oracle = Enum.find(source(), &(&1["name"] == "s02_prism_strings"))["response"]

    assert Jason.decode!(body) ==
             Jason.decode!(oracle["body"])
             |> Enum.map(
               &Map.update!(&1, "thumbnail_url", fn url ->
                 String.replace(url, "a4951000-0000-4000-8000-000000000001", link)
               end)
             )

    assert {200, headers, @image} =
             response(c, link, "photos/public-0/thumbnail?source=photoprism")

    assert {"content-type", "image/jpeg"} in headers
    assert {"content-disposition", "inline"} in headers
    assert Enum.any?(requests(c), &(&1.path == "/api/v1/t/public-0/owner-preview/tile_500"))

    assert Enum.all?(
             requests(c) |> Enum.filter(&(&1.path == "/api/v1/photos")),
             &(values(&1.headers, "authorization") == ["Bearer synthetic-owner-prism"])
           )

    refute Enum.any?(requests(c), &String.contains?(&1.path, "foreign-preview"))
    no_upstream!(c.upstream)
    assert commands() == []
    assert effects() == c.effects
  end

  @tag a12f3b_case: "S02F1"
  test "zone expansion between filtering and fingerprinting cannot poison thumbnail grants", c do
    for entry <- [:list, :cold_thumbnail] do
      Repo.query!("UPDATE tags SET privacy_radius_meters=100 WHERE user_id=$1", [c.owner])
      configure(c, [asset("public-0", "52.5", "13.4")])
      link = link!(c.owner, 0, c.trip)
      parent = self()
      handler = {__MODULE__, :zone_expansion, entry}

      :telemetry.attach(
        handler,
        [:dawarich, :repo, :query],
        fn _, _, meta, owner ->
          if String.starts_with?(meta.query, "SELECT p.longitude::float8,p.latitude::float8") and
               Process.get(handler) != true do
            Process.put(handler, true)
            Repo.query!("UPDATE tags SET privacy_radius_meters=1000000 WHERE user_id=$1", [owner])
            send(parent, {:zone_expanded, owner})
          end
        end,
        c.owner
      )

      on_exit(fn -> :telemetry.detach(handler) end)
      action = if entry == :list, do: "photos", else: "photos/public-0/thumbnail?source=immich"
      assert {200, _, _} = response(c, link, action)
      assert_receive {:zone_expanded, owner}
      assert owner == c.owner
      :telemetry.detach(handler)

      refute Dawarich.SharedApi.Privacy.visible_photo?(
               %{"latitude" => "52.5", "longitude" => "13.4"},
               Closure.zones(c.owner)
             )

      before_denial = requests(c)
      get = response(c, link, "photos/public-0/thumbnail?source=immich")
      head = response(c, link, "photos/public-0/thumbnail?source=immich", [], "HEAD")
      assert {elem(get, 0), elem(head, 0)} == {404, 404}
      assert elem(get, 2) == ""
      assert elem(head, 2) == ""
      assert Enum.drop(requests(c), length(before_denial)) == []
    end

    assert commands() == []
    no_upstream!(c.upstream)
    assert effects() == c.effects
  end

  @tag a12f3b_case: "S02F2"
  test "warm thumbnail grants expire when the shared trip window excludes the photo", c do
    configure(c, [asset("public-0")])
    link = link!(c.owner, 0, c.trip)
    assert {200, _, body} = response(c, link, "photos")
    assert [%{"id" => "public-0"}] = Jason.decode!(body)
    assert {200, _, @image} = response(c, link, "photos/public-0/thumbnail?source=immich")

    Repo.query!(
      "UPDATE trips SET started_at=started_at + interval '1 day', ended_at=ended_at + interval '1 day' WHERE id=$1",
      [c.trip]
    )

    before_denial = requests(c)
    get = response(c, link, "photos/public-0/thumbnail?source=immich")
    head = response(c, link, "photos/public-0/thumbnail?source=immich", [], "HEAD")
    assert {elem(get, 0), elem(head, 0)} == {404, 404}
    assert elem(get, 2) == ""
    assert elem(head, 2) == ""

    assert Enum.all?(Enum.drop(requests(c), length(before_denial)), fn request ->
             request.path == "/api/search/metadata"
           end)

    assert commands() == []
    no_upstream!(c.upstream)
    assert effects() == c.effects
  end

  defp resource!(table, owner) do
    {first, last, extra, value} =
      if table == "trips",
        do: {"started_at", "ended_at", "name", "'Synthetic trip'"},
        else:
          {"start_at", "end_at", "original_path",
           "ST_GeomFromText('LINESTRING(13 52,13.1 52.1)',4326)"}

    [[id]] =
      Repo.query!(
        "INSERT INTO #{table}(user_id,#{first},#{last},#{extra},created_at,updated_at) VALUES($1,'2026-03-29 00:00:00','2026-03-29 01:00:00',#{value},NOW(),NOW()) RETURNING id",
        [owner]
      ).rows

    id
  end

  defp zone!(owner) do
    [[place]] =
      Repo.query!(
        "INSERT INTO places(user_id,name,latitude,longitude,source,created_at,updated_at) VALUES($1,'Synthetic zone',52,13,0,NOW(),NOW()) RETURNING id",
        [owner]
      ).rows

    [[tag]] =
      Repo.query!(
        "INSERT INTO tags(user_id,name,privacy_radius_meters,created_at,updated_at) VALUES($1,'Synthetic privacy',100,NOW(),NOW()) RETURNING id",
        [owner]
      ).rows

    Repo.query!(
      "INSERT INTO taggings(tag_id,taggable_type,taggable_id,created_at,updated_at) VALUES($1,'Place',$2,NOW(),NOW())",
      [tag, place]
    )
  end

  defp link!(owner, type, resource) do
    id = Ecto.UUID.generate()
    settings = %{"show_photos" => true, "start_date" => "2026-03-29", "end_date" => "2026-03-29"}

    Repo.query!(
      "INSERT INTO shared_links(id,user_id,resource_type,resource_id,name,settings,created_at,updated_at) VALUES($1::text::uuid,$2,$3,$4,'Synthetic share',$5,NOW(),NOW())",
      [id, owner, type, resource, settings]
    )

    on_exit(fn -> clear_grants(id) end)
    id
  end

  defp set!(id, column, value),
    do: Repo.query!("UPDATE shared_links SET #{column}=$2 WHERE id=$1::text::uuid", [id, value])

  defp requests(c), do: Agent.get(c.state, & &1.requests)

  defp configure(c, photos, failure \\ nil) do
    ProviderCache.invalidate(c.owner)

    for [id] <- Repo.query!("SELECT id::text FROM shared_links WHERE user_id=$1", [c.owner]).rows do
      clear_grants(id)
    end

    parent = self()
    Agent.update(c.state, &%{&1 | immich: photos, failure: failure, parent: parent})
  end

  defp clear_grants(id) do
    case Dawarich.Redis.cache_command(["KEYS", "shared_link/#{id}/photo_ids/*"]) do
      {:ok, [_ | _] = keys} -> Dawarich.Redis.cache_command(["UNLINK" | keys])
      _ -> :ok
    end
  end

  defp asset(id, lat \\ 52.5, lon \\ 13.4),
    do: %{
      "id" => id,
      "type" => "IMAGE",
      "fileCreatedAt" => "2026-03-29T00:30:00Z",
      "exifInfo" => %{"latitude" => lat, "longitude" => lon}
    }

  defp prism(id, lat, lon),
    do: %{
      "Hash" => id,
      "Type" => "image",
      "TakenAt" => "2026-03-29T00:30:00Z",
      "Lat" => lat,
      "Lng" => lon
    }

  defp source, do: File.read!("test/fixtures/api_shared/s02.json") |> Jason.decode!()

  defp effects do
    Map.new(~w(job_outbox active_storage_blobs active_storage_attachments), fn table ->
      {table, Repo.query!("SELECT count(*) FROM #{table}").rows}
    end)
  end

  defp response(c, id, action, headers \\ [], method \\ "GET"),
    do:
      c.port
      |> request(
        "/api/v1/shared/#{id}/#{action}",
        [{"Accept", "application/json"} | headers],
        method
      )
      |> read_response(method: method)

  defp cookie(id, phrase) do
    name = "shared_link_#{id}"

    value =
      RailsCookies.encrypt(
        SharedLinkCookie.unlock_token(id, phrase),
        name,
        RailsSecret.fetch(),
        DateTime.add(@now, 3600)
      )

    [{"Cookie", "#{name}=#{value}"}]
  end

  defp release_timeouts do
    receive do
      {:held_provider, pid} ->
        send(pid, :release)
        release_timeouts()
    after
      0 -> :ok
    end
  end
end
