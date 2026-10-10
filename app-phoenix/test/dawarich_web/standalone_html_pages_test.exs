defmodule DawarichWeb.StandaloneHtmlPagesTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.{ApiGolden, RailsUser}
  @endpoint DawarichWeb.Endpoint
  @fixture_now ~U[2026-10-07 12:00:00Z]

  setup do
    previous = Map.new(~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL), &{&1, System.get_env(&1)})
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true", "FORCE_SSL" => "false"})

    on_exit(fn ->
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    fixture = File.read!("test/fixtures/standalone/html_pages.json") |> Jason.decode!()

    for actor <- fixture["users"] do
      actor = Map.new(actor, fn {key, value} -> {String.to_atom(key), value} end)

      actor =
        Enum.reduce(~w(active_until created_at updated_at last_sign_in_at)a, actor, fn key, row ->
          Map.update!(row, key, fn value -> if value, do: NaiveDateTime.from_iso8601!(value) end)
        end)

      RailsUser.insert!(actor)
    end

    for table <-
          ~w(imports points tracks trips places tags notifications stats digests shared_links families family_memberships family_invitations family_location_requests achievement_progresses trip_sources) do
      for row <- fixture["rows"][table], do: ApiGolden.insert!(table, row)
    end

    Dawarich.State.put_registration_enabled(Repo, false)
    Dawarich.Jobs.Ownership.put!(Repo, "command:trips.calculate", :oban)
    %{fixture: fixture}
  end

  @tag :standalone_html_sweep
  test "every Rails HTML GET page and its captured form query renders natively without handback errors",
       %{fixture: fixture} do
    assert length(fixture["routes"]) > 70

    results =
      for route <- fixture["routes"] do
        result = request(fixture["user_id"], route["target"])

        if route["rails_status"] == 200 and route["html"] do
          {route["target"], result,
           route["native_status"] ||
             if(URI.parse(route["target"]).path == "/sidekiq", do: 302, else: 200)}
        end
      end

    failures =
      for {target, result, expected} <- Enum.reject(results, &is_nil/1),
          result != expected,
          do: {target, result, expected}

    assert failures == []
  end

  @tag :standalone_resources
  test "standalone public trip and track pages honor sharing flags privacy zones and revoked grants",
       %{fixture: fixture} do
    owner = fixture["user_id"]
    trip_link = "a9480100-0000-4000-8000-000000000001"
    track_link = "a9480100-0000-4000-8000-000000000002"

    Repo.query!(
      "INSERT INTO action_text_rich_texts(name,body,record_type,record_id,created_at,updated_at) VALUES('description','<div>Owner-only description</div>','Trip',94801,now(),now())"
    )

    for {id, type} <- [{trip_link, "trip"}, {track_link, "track"}] do
      conn = page(owner, "/s/" <> id)
      assert conn.status == 200
      assert String.contains?(conn.resp_body, ~s(data-controller="shared-trip-map")) == true

      assert String.contains?(conn.resp_body, ~s(data-shared-trip-map-link-id-value="#{id}")) ==
               true

      assert String.contains?(conn.resp_body, "synthetic-html-pages-key") == false
      if type == "trip", do: assert(conn.resp_body =~ "Owner-only description")
    end

    Repo.query!("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [
      trip_link,
      %{
        "show_route" => false,
        "show_stats" => false,
        "show_description" => false,
        "show_days" => false,
        "show_day_notes" => false,
        "show_photos" => false
      }
    ])

    hidden = page(owner, "/s/" <> trip_link)
    assert hidden.status == 200
    assert String.contains?(hidden.resp_body, "Owner-only description") == false
    assert String.contains?(hidden.resp_body, ~s(data-controller="shared-trip-map")) == false
    assert String.contains?(hidden.resp_body, "data-day-dot") == false

    Repo.query!("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [
      trip_link,
      %{"show_description" => false, "show_photos" => false}
    ])

    Repo.query!("UPDATE tags SET privacy_radius_meters=1000 WHERE id=94801")

    Repo.query!(
      "UPDATE places SET latitude=ST_Y(p.lonlat::geometry),longitude=ST_X(p.lonlat::geometry) FROM points p WHERE places.id=94801 AND p.id=94801"
    )

    Repo.query!(
      "INSERT INTO taggings(tag_id,taggable_type,taggable_id,created_at,updated_at) VALUES(94801,'Place',94801,now(),now())"
    )

    private = page(owner, "/s/" <> trip_link)
    assert private.status == 200
    assert String.contains?(private.resp_body, "No data") == true
    assert String.contains?(private.resp_body, "10:00") == false
    Repo.query!("UPDATE shared_links SET revoked_at=now() WHERE id=$1::text::uuid", [trip_link])
    assert page(owner, "/s/" <> trip_link).status == 404
    Repo.query!("UPDATE tracks SET user_id=94802 WHERE id=94801")
    missing = page(owner, "/s/" <> track_link)
    assert missing.status == 200
    assert String.contains?(missing.resp_body, ~s(data-controller="shared-trip-map")) == false
  end

  @tag :review_family_cache
  test "review family trip response must prohibit storage", %{fixture: fixture} do
    links = shared_page_links(fixture)

    for id <- links do
      conn = page(94802, "/s/" <> id)
      assert conn.status == 200
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
      assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
    end

    Repo.query!("DELETE FROM trips WHERE id=94801")
    missing = page(94802, "/s/" <> hd(links))
    assert missing.status == 200
    assert get_resp_header(missing, "cache-control") == ["private, no-store"]

    Repo.query!(
      "UPDATE shared_links SET magic_phrase='synthetic-phrase' WHERE id=$1::text::uuid",
      [hd(links)]
    )

    prompt = page(94802, "/s/" <> hd(links))
    assert prompt.status == 401
    assert get_resp_header(prompt, "cache-control") == ["private, no-store"]
    assert String.contains?(prompt.resp_body, "mobile-navigation-menu") == true

    for {phrase, status} <- [{"wrong", 401}, {"synthetic-phrase", 302}] do
      body = URI.encode_query(%{"phrase" => phrase})

      unlock =
        RailsUser.signed_in(94802)
        |> assign(:now, @fixture_now)
        |> put_req_header("accept", "text/html")
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> put_req_header("content-length", to_string(byte_size(body)))
        |> post("/s/" <> hd(links) <> "/unlock", body)

      assert unlock.status == status
      assert get_resp_header(unlock, "cache-control") == ["private, no-store"]
    end

    Repo.query!("DELETE FROM family_memberships WHERE user_id=94802")
    assert page(94802, "/s/" <> hd(links)).status == 404
    anonymous = build_conn() |> put_req_header("accept", "text/html") |> get("/s/" <> hd(links))
    assert anonymous.status == 404
  end

  @tag :review_family_layout
  test "review family trip retains the application navigation", %{fixture: fixture} do
    Repo.query!("UPDATE users SET theme='light' WHERE id=94802")

    for id <- shared_page_links(fixture) do
      conn = page(94802, "/s/" <> id)
      assert conn.status == 200
      assert String.contains?(conn.resp_body, "mobile-navigation-menu") == true
      document = LazyHTML.from_document(conn.resp_body)
      link = Dawarich.SharedLinks.active(id, DateTime.utc_now())
      title = DawarichWeb.SharedPages.title(%{locale: "en", link: link})

      assert LazyHTML.query(document, "title") |> LazyHTML.text() ==
               DawarichWeb.Layouts.page_title("en", title)

      assert LazyHTML.query(document, ~s(meta[property="og:title"]))
             |> LazyHTML.attribute("content") == [link.name]

      assert String.contains?(conn.resp_body, ~s(data-theme="dawarich")) == true
      assert String.contains?(conn.resp_body, ~s(data-self-hosted="true")) == true
      assert String.contains?(conn.resp_body, "utm_medium=public_share") == false

      Repo.query!(
        "UPDATE shared_links SET settings=settings - 'audience' - 'family_id' WHERE id=$1::text::uuid",
        [id]
      )

      public = page(94802, "/s/" <> id)
      assert public.status == 200
      assert String.contains?(public.resp_body, "utm_medium=public_share") == true
      assert String.contains?(public.resp_body, "mobile-navigation-menu") == false
      assert get_resp_header(public, "cache-control") == ["max-age=0, private, must-revalidate"]
    end
  end

  @tag :review_trip_gallery
  test "review trip gallery retains the 101st allowed photo", %{fixture: fixture} do
    id = "a9480100-0000-4000-8000-000000000001"

    Repo.query!("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [
      id,
      %{"show_photos" => true}
    ])

    Repo.query!("UPDATE trips SET ended_at='2026-03-02 23:59:59' WHERE id=94801")
    Repo.query!("UPDATE tags SET privacy_radius_meters=1000 WHERE id=94801")
    Repo.query!("UPDATE places SET latitude=10,longitude=10 WHERE id=94801")

    Repo.query!(
      "INSERT INTO taggings(tag_id,taggable_type,taggable_id,created_at,updated_at) VALUES(94801,'Place',94801,now(),now())"
    )

    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    link = Dawarich.SharedLinks.active(id, DateTime.utc_now())
    context = %{range: {from, to}} = Dawarich.SharedApi.Photos.grant_context(link)

    photos =
      for i <- 1..101 do
        Map.new(
          ~w(id latitude longitude localDateTime capturedAt originalFileName city state country type orientation source),
          &{&1, nil}
        )
        |> Map.merge(%{
          "id" => "synthetic-photo-#{i}",
          "latitude" => 51.3,
          "longitude" => 12.3,
          "source" => "immich",
          "capturedAt" => if(i == 101, do: "2026-03-02T12:00:00Z", else: "2026-03-01T12:00:00Z")
        })
      end

    key = "photos_search/#{fixture["user_id"]}/v2/#{from}/#{to}"

    private =
      Map.merge(hd(photos), %{
        "id" => "synthetic-private-photo",
        "latitude" => 10,
        "longitude" => 10
      })

    unmappable = Map.merge(hd(photos), %{"id" => "synthetic-unmappable-photo", "latitude" => nil})
    Dawarich.Photos.ProviderCache.put(key, photos ++ [private, unmappable])

    on_exit(fn ->
      {:ok, redis} = Redix.start_link(System.fetch_env!("PHOENIX_TEST_REDIS_URL"), database: 0)
      Redix.command!(redis, ["DEL", key, Dawarich.SharedApi.Closure.photo_ids_key(link, context)])
      Redix.stop(redis)
    end)

    resource = Dawarich.SharedLinks.ResourcePage.load(link)
    assert Enum.sum(Enum.map(resource.days, &length(&1.photos))) == 101
    later = Enum.find(resource.days, &(&1.date == ~D[2026-03-02]))
    assert Enum.map(later.photos, & &1["id"]) == ["synthetic-photo-101"]
    conn = page(fixture["user_id"], "/s/" <> id)
    assert conn.status == 200

    assert String.contains?(conn.resp_body, "/photos/synthetic-photo-101/thumbnail?source=immich") ==
             true

    assert {:ok, api_photos} = Dawarich.SharedApi.Photos.response(link, :photos)
    assert length(api_photos) == 100
    api = page(fixture["user_id"], "/api/v1/shared/" <> id <> "/photos")
    assert api.status == 200
    assert length(Jason.decode!(api.resp_body)) == 100
    refute Dawarich.SharedApi.Closure.allowed_photo?(link, "immich", "synthetic-private-photo")
    refute Dawarich.SharedApi.Closure.allowed_photo?(link, "immich", "synthetic-unmappable-photo")
    assert Dawarich.SharedApi.Closure.allowed_photo?(link, "immich", "synthetic-photo-101")
    refute Dawarich.SharedApi.Closure.allowed_photo?(link, "immich", "foreign-photo")

    Repo.query!("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [
      id,
      %{"show_photos" => false}
    ])

    hidden =
      Dawarich.SharedLinks.ResourcePage.load(Dawarich.SharedLinks.active(id, DateTime.utc_now()))

    assert Enum.all?(hidden.days, &(&1.photos == []))
  end

  defp shared_page_links(fixture) do
    links =
      ~w(a9480100-0000-4000-8000-000000000001 a9480100-0000-4000-8000-000000000002 a9480100-0000-4000-8000-000000000003 a9480100-0000-4000-8000-000000000004)

    stamp = NaiveDateTime.utc_now()

    for {id, type} <- Enum.zip(Enum.drop(links, 2), [2, 3]) do
      Repo.insert_all("shared_links", [
        %{
          id: Ecto.UUID.dump!(id),
          name: "Synthetic family share",
          user_id: fixture["user_id"],
          resource_type: type,
          settings: %{},
          created_at: stamp,
          updated_at: stamp
        }
      ])
    end

    for id <- links do
      Repo.query!("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [
        id,
        %{
          "audience" => "family",
          "family_id" => "94801",
          "start_date" => "2026-03-01",
          "end_date" => "2026-03-02"
        }
      ])
    end

    links
  end

  defp page(user_id, target) do
    RailsUser.signed_in(user_id)
    |> assign(:now, @fixture_now)
    |> put_req_header("accept", "text/html")
    |> get(target)
  end

  defp request(user_id, target) do
    RailsUser.signed_in(user_id)
    |> assign(:now, @fixture_now)
    |> put_req_header("accept", "text/html")
    |> get(target)
    |> Map.fetch!(:status)
  rescue
    error ->
      {:exception, error.__struct__,
       Enum.take(
         Enum.map(__STACKTRACE__, fn {module, function, _, location} ->
           {module, function, location[:line]}
         end),
         3
       )}
  end
end
