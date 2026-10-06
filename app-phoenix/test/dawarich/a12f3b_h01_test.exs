defmodule Dawarich.A12f3bH01Test do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  alias Dawarich.Test.{FrameSeeds, RailsUser, RawHTTP}
  alias Dawarich.Test.A12f3bShareCase, as: Shares
  alias DawarichWeb.{Endpoint, Router, RailsCsrf}

  setup do
    <<a::16, b::16, c::16, d::16, e::16, f::16>> = :crypto.strong_rand_bytes(12)
    Process.put(:h01_remote_ip, {0x2001, 0xDB8, a, b, c, d, e, f})
    saved = Map.new(~w(DAWARICH_RAILS SELF_HOSTED JWT_SECRET_KEY), &{&1, System.get_env(&1)})
    routes = Application.get_env(:dawarich, :rails_routes)
    auth = Application.get_env(:dawarich, :phoenix_auth)
    upstream = Application.get_env(:dawarich, :rails_upstream)
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    System.put_env("JWT_SECRET_KEY", "h01-synthetic-subscription-secret")
    Application.put_env(:dawarich, :rails_routes, [])
    Application.put_env(:dawarich, :phoenix_auth, [])
    Application.put_env(:dawarich, :rails_upstream, nil)

    on_exit(fn ->
      for {key, value} <- saved do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end

      Application.put_env(:dawarich, :rails_routes, routes)
      Application.put_env(:dawarich, :phoenix_auth, auth)
      Application.put_env(:dawarich, :rails_upstream, upstream)
    end)

    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("owner_en"))
    %{owner: owner, outsider: Dawarich.Accounts.get(90103)}
  end

  @tag a12f3b_case: "H01a"
  test "every retained part B source route has an executable native owner", c do
    for {method, path, plug} <- declarations() do
      route = Phoenix.Router.route_info(Router, method, path, "www.example.com")
      assert is_map(route), "missing #{method} #{path}"
      assert route.plug == plug, "wrong owner for #{method} #{path}"
      assert Code.ensure_loaded?(plug)
      assert function_exported?(plug, :call, 2)

      assert Enum.count(
               Router.__routes__(),
               &(String.upcase(to_string(&1.verb)) == method and &1.path == route.route)
             ) == 1
    end

    assert request(c.owner, "GET", "/family/invitations/new").status == 404
    assert request(c.owner, "GET", "/family").status == 200

    %{phoenix_live_view: {_, _, _, family_session}} =
      Phoenix.Router.route_info(Router, "GET", "/family", "www.example.com")

    assert Enum.map(family_session.extra.on_mount, & &1.id) ==
             [{DawarichWeb.LiveAuth, :default}, {DawarichWeb.FamilyGate, :default}]

    assert request(c.outsider, "POST", "/family", %{"family" => %{"name" => "Mounted family"}}).status ==
             302

    assert Repo.query!("SELECT name FROM families WHERE creator_id=$1", [c.outsider.id]).rows == [
             ["Mounted family"]
           ]

    assert request(c.outsider, "PATCH", "/family", %{"family" => %{"name" => "Mounted update"}}).status ==
             302

    assert Repo.query!("SELECT name FROM families WHERE creator_id=$1", [c.outsider.id]).rows == [
             ["Mounted update"]
           ]

    actor = Shares.seed!()

    for {type, base} <- [
          {"track", "/tracks/99103/share_link"},
          {"timeline", "/share_links/timeline"}
        ] do
      get = request(actor, "GET", base <> "/new")
      head = request(actor, "HEAD", base <> "/new")
      assert get.status == 200
      assert head.status == get.status
      assert get_resp_header(head, "content-type") == get_resp_header(get, "content-type")
      assert head.resp_body == ""
      assert request(actor, "POST", base, Shares.params(type)).status == 302
      assert request(actor, "POST", base <> "/revoke", %{"_method" => "patch"}).status == 302
      assert request(actor, "POST", base <> "/regenerate").status == 302
      assert request(actor, "POST", base <> "/regenerate_phrase").status == 302
      assert request(actor, "POST", base, %{"_method" => "delete"}).status == 302
    end

    assert request(c.owner, "POST", "/posters", %{"poster" => %{"name" => "Mounted poster"}}).status ==
             302

    [[id]] =
      Repo.query!("SELECT id FROM posters WHERE user_id=$1 ORDER BY id DESC LIMIT 1", [c.owner.id]).rows

    assert request(c.owner, "DELETE", "/posters/#{id}").status == 303
    assert Repo.query!("SELECT id FROM posters WHERE id=$1", [id]).rows == []
    assert_settings(c.owner, c.outsider)
    assert_demo_flow(c.owner)
  end

  @tag a12f3b_case: "H01c"
  test "mounted achievement routes serve standalone pages unlocks and public PNGs", c do
    Dawarich.Test.AchievementSilhouettes.clear()
    on_exit(&Dawarich.Test.AchievementSilhouettes.clear/0)
    uuid = "a12f0000-0000-4000-8000-000000090101"
    path = "/shared/achievements/#{uuid}"

    Repo.query!(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,sharing_enabled,sharing_uuid,created_at,updated_at) VALUES($1,'country_de','{}',true,$2,now(),now())",
      [c.owner.id, uuid]
    )

    image_request = fn method ->
      Plug.Test.conn(method, path <> "/og.png")
      |> Map.put(:remote_ip, Process.get(:h01_remote_ip))
      |> put_req_header("accept", "image/png")
      |> Endpoint.call(Endpoint.init([]))
    end

    image = image_request.("GET")
    assert image.status == 200

    assert <<137, 80, 78, 71, 13, 10, 26, 10, _::binary-size(8), 1200::32, 630::32, _::binary>> =
             image.resp_body

    assert get_resp_header(image, "content-type") == ["image/png"]
    assert get_resp_header(image, "cache-control") == ["private, no-store"]
    assert get_resp_header(image, "content-disposition") == ["inline"]
    head = image_request.("HEAD")
    assert head.status == image.status and head.resp_body == ""
    assert head.resp_headers == image.resp_headers
    route = Phoenix.Router.route_info(Router, "GET", path <> "/og.png", "www.example.com")
    assert route.plug == DawarichWeb.AchievementPublicImage
    assert route.pipe_through == [:achievement_image]
    assert route.rails_key == "achievements"

    assert Enum.count(Router.__routes__(), &(&1.path == route.route)) == 1

    page_request = fn method, target ->
      Plug.Test.conn(method, target)
      |> Map.put(:remote_ip, Process.get(:h01_remote_ip))
      |> put_req_header("accept", "text/html")
      |> put_req_header(
        "cookie",
        "_dawarich_session=" <> RailsUser.cookie(RailsUser.session(c.owner.id))
      )
      |> Endpoint.call(Endpoint.init([]))
    end

    for target <- ["/achievements", "/achievements/country_de", path, path <> "?embed=1"] do
      get = page_request.("GET", target)
      head = page_request.("HEAD", target)
      assert get.status == 200, target
      assert get_resp_header(get, "content-type") == ["text/html; charset=utf-8"]
      assert head.status == get.status and head.resp_body == ""
      assert get_resp_header(head, "content-type") == get_resp_header(get, "content-type")
    end

    for {target, status} <- [
          {"/achievements/country_fr", 302},
          {"/achievements/border_hopper", 302},
          {"/achievements/missing", 404}
        ],
        do: assert(page_request.("GET", target).status == status)

    assert request(c.owner, "POST", "/achievements/unlocks/next").status == 204

    [[id]] =
      Repo.query!(
        "INSERT INTO achievement_unlock_events(user_id,kind,key,created_at,updated_at) VALUES($1,'geography','FR',now(),now()) RETURNING id",
        [c.owner.id]
      ).rows

    invalid =
      request(c.owner, "POST", "/achievements/unlocks/next", %{"authenticity_token" => "invalid"})

    assert invalid.status == 422

    assert Repo.query!(
             "SELECT claim_token,claimed_at,seen_at FROM achievement_unlock_events WHERE id=$1",
             [id]
           ).rows == [[nil, nil, nil]]

    next = request(c.owner, "POST", "/achievements/unlocks/next")
    assert next.status == 200
    card = Jason.decode!(next.resp_body)
    assert card["id"] == id
    assert is_binary(card["html"]) and card["html"] != ""

    assert Repo.query!("SELECT claim_token FROM achievement_unlock_events WHERE id=$1", [id]).rows ==
             [[card["token"]]]

    assert request(c.owner, "POST", "/achievements/unlocks/#{id}/seen", %{
             "claim_token" => card["token"]
           }).status == 204

    assert request(c.owner, "POST", "/achievements/unlocks/dismiss", %{"batch_end_id" => id}).status ==
             204

    assert request(c.owner, "POST", "/achievements/unlocks/next").status == 204

    assert request(c.owner, "PATCH", "/achievements/country_de/toggle_sharing", %{
             "enabled" => "0"
           }).status ==
             302

    denied = image_request.("GET")
    assert denied.status == 404 and denied.resp_body == ""
    assert get_resp_header(denied, "cache-control") == ["private, no-store"]
    assert image_request.("HEAD").status == 404

    System.delete_env("DAWARICH_RAILS")
    Application.put_env(:dawarich, :rails_routes, ["achievements"])
    server = RawHTTP.listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, server.port})

    receiver =
      Task.async(fn ->
        socket = RawHTTP.accept(server)
        {head, _} = RawHTTP.read_head(socket)

        RawHTTP.reply(
          socket,
          "HTTP/1.1 209 Rails\r\nContent-Length: 6\r\nConnection: close\r\n\r\nsource"
        )

        :gen_tcp.close(socket)
        head
      end)

    pinned = image_request.("GET")
    assert pinned.status == 209 and pinned.resp_body == "source"
    assert RawHTTP.request_line(Task.await(receiver)) == "GET #{path}/og.png HTTP/1.1"
  end

  @tag a12f3b_case: "H01d"
  test "mounted integration forms save nested settings and publish native photo imports", c do
    for method <- ~w(POST PATCH PUT) do
      route =
        Phoenix.Router.route_info(Router, method, "/settings/integrations", "www.example.com")

      assert is_map(route), "missing integration #{method}"
      assert route.plug == DawarichWeb.IntegrationActions
      assert route.pipe_through == [:integration_forms]

      assert Enum.count(
               Router.__routes__(),
               &(&1.path == route.route and to_string(&1.verb) == String.downcase(method))
             ) == 1
    end

    route =
      Phoenix.Router.route_info(Router, "POST", "/settings/background_jobs", "www.example.com")

    assert route.plug == DawarichWeb.IntegrationJobActions
    assert Enum.count(Router.__routes__(), &(&1.path == route.route and &1.verb == :post)) == 1
    session = RailsUser.session(c.owner.id)

    for hosted <- ~w(true false) do
      System.put_env("SELF_HOSTED", hosted)

      for {method, override} <- [{:patch, nil}, {:put, nil}, {:post, "patch"}] do
        params = %{
          "settings" => %{
            "immich_url" => "",
            "immich_api_key" => "synthetic-mounted-immich",
            "ignored" => "discard"
          }
        }

        params = if override, do: Map.put(params, "_method", override), else: params

        response =
          browser_request(session, method, "/settings/integrations?service=immich", params)

        assert response.status == 302

        assert get_resp_header(response, "location") == [
                 "http://www.example.com/settings/integrations?service=immich"
               ]

        assert get_resp_header(response, "cache-control") == ["no-cache"]
        saved = Dawarich.Accounts.settings(c.owner.id)
        assert saved["immich_api_key"] == "synthetic-mounted-immich"
        refute Map.has_key?(saved, "ignored")
      end

      masked =
        browser_request(session, :post, "/settings/integrations?service=immich", %{
          "_method" => "put",
          "settings" => %{"immich_api_key" => "********"}
        })

      assert masked.status == 302

      assert Dawarich.Accounts.settings(c.owner.id)["immich_api_key"] ==
               "synthetic-mounted-immich"

      for provider <- ~w(immich photoprism) do
        Dawarich.Jobs.Ownership.put!(Repo, "command:imports.#{provider}_geodata", :oban)

        response =
          browser_request(
            session,
            :post,
            "/settings/background_jobs?job_name=start_#{provider}_import",
            %{}
          )

        assert response.status == 302
        assert get_resp_header(response, "location") == ["http://www.example.com/imports"]
      end
    end

    expected =
      for kind <- ~w(imports.immich_geodata imports.photoprism_geodata),
          _ <- 1..2,
          do: [kind, 1, %{"user_id" => c.owner.id, "time_zone" => "Europe/Berlin"}]

    assert Repo.query!(
             "SELECT command_type,command_version,payload FROM job_outbox ORDER BY command_type"
           ).rows == expected

    assert commands() == []
    before = Dawarich.Accounts.settings(c.owner.id)

    denied =
      browser_request(session, :post, "/settings/integrations", %{
        "_method" => "patch",
        "settings" => %{"immich_api_key" => "denied"},
        "authenticity_token" => "invalid"
      })

    assert denied.status == 422
    assert Dawarich.Accounts.settings(c.owner.id) == before

    assert browser_request(session, :post, "/settings/background_jobs?job_name=unknown", %{}).status ==
             422

    Dawarich.Jobs.Ownership.put!(Repo, "command:imports.photoprism_geodata", :sidekiq)

    assert browser_request(
             session,
             :post,
             "/settings/background_jobs?job_name=start_photoprism_import",
             %{}
           ).status == 503

    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[4]]
  end

  @tag a12f3b_case: "H01b"
  test "part B handback occurs before native effects and final native transport errors are source compatible",
       c do
    actor = Shares.seed!()
    System.delete_env("DAWARICH_RAILS")

    for {key, user, path, params} <- [
          {"family", c.outsider, "/family", %{"family" => %{"name" => "Must hand back"}}},
          {nil, c.owner, "/family/invitations",
           %{"family_invitation" => %{"email" => "native-handoff@example.test"}}},
          {"tracks", actor, "/tracks/99103/share_link", Shares.params("track")},
          {"trip_shares", actor, "/trips/99101/share_link", Shares.params("track")},
          {"share_links", actor, "/share_links/timeline", Shares.params("timeline")},
          {"posters", c.owner, "/posters", %{"poster" => %{"name" => "Must hand back"}}},
          {nil, c.owner, "/settings/general", %{"_method" => "patch", "locale" => "de"}},
          {nil, c.owner, "/settings/general/verify_supporter", %{}},
          {nil, c.owner, "/settings/changelog_consent",
           %{"_method" => "patch", "decision" => "granted"}},
          {nil, c.owner, "/settings/generate_api_key", %{}},
          {nil, c.owner, "/settings/onboarding", %{"_method" => "put"}},
          {nil, c.owner, "/settings/onboarding/demo_data", %{}},
          {nil, c.owner, "/settings/onboarding/demo_data", %{"_method" => "delete"}},
          {nil, c.owner, "/settings/integrations?service=immich",
           %{"_method" => "patch", "settings" => %{"immich_api_key" => "synthetic-handback"}}},
          {nil, c.owner, "/settings/background_jobs?job_name=start_immich_import", %{}},
          {nil, c.owner, "/notifications/mark_as_read", %{}},
          {nil, c.owner, "/notifications/destroy_all", %{}},
          {nil, c.owner, "/notifications/1", %{"_method" => "delete"}},
          {nil, c.outsider, "/family/location_requests?a=%ZZ", "target_user_id=90102"},
          {nil, c.outsider, "/family/location_requests", "a=%4"},
          {nil, c.outsider, "/family/location_requests", "_method=delete"}
        ] do
      before = footprint()
      Application.put_env(:dawarich, :rails_routes, if(key, do: [key], else: []))
      server = RawHTTP.listen()
      Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, server.port})
      session = RailsUser.session(user.id)
      cookie = RailsUser.cookie(session)

      body =
        if is_binary(params),
          do:
            "authenticity_token=" <>
              URI.encode_www_form(RailsCsrf.masked_token(session)) <> "&" <> params,
          else:
            Plug.Conn.Query.encode(
              Map.put(params, "authenticity_token", RailsCsrf.masked_token(session))
            )

      receiver =
        Task.async(fn ->
          socket = RawHTTP.accept(server)
          {head, rest} = RawHTTP.read_head(socket)
          [length] = RawHTTP.header(head, "content-length")
          received = RawHTTP.read_at_least(socket, rest, String.to_integer(length))

          RawHTTP.reply(
            socket,
            "HTTP/1.1 209 Rails\r\nContent-Length: 6\r\nConnection: close\r\n\r\nsource"
          )

          :gen_tcp.close(socket)
          {head, received}
        end)

      response = raw_request("POST", path, body, cookie)
      assert response.status == 209
      {head, received} = Task.await(receiver)
      :gen_tcp.close(server.listen)
      assert response.resp_body == "source"
      assert RawHTTP.request_line(head) == "POST #{path} HTTP/1.1"
      assert RawHTTP.header(head, "cookie") == ["_dawarich_session=" <> cookie]
      assert received == body
      assert footprint() == before
    end

    Application.put_env(:dawarich, :rails_routes, [])
    Application.put_env(:dawarich, :rails_upstream, nil)
    System.put_env("DAWARICH_RAILS", "off")
    before = footprint()

    for {method, path, params} <- [
          {"PATCH", "/settings/general", %{"locale" => "de"}},
          {"POST", "/settings/general/verify_supporter", %{}},
          {"PATCH", "/settings/changelog_consent", %{"decision" => "granted"}},
          {"POST", "/settings/generate_api_key", %{}},
          {"PUT", "/settings/onboarding", %{}},
          {"POST", "/settings/onboarding/demo_data", %{}},
          {"DELETE", "/settings/onboarding/demo_data", %{}},
          {"PATCH", "/settings/integrations", %{"settings" => %{"immich_api_key" => "denied"}}},
          {"POST", "/settings/background_jobs?job_name=start_immich_import", %{}},
          {"POST", "/notifications/mark_as_read", %{}},
          {"POST", "/notifications/destroy_all", %{}},
          {"DELETE", "/notifications/1", %{}}
        ] do
      assert request(c.owner, method, path, Map.put(params, "authenticity_token", "invalid")).status ==
               422
    end

    assert raw_request("PATCH", "/settings/general", "", "").status == 302
    assert raw_request("GET", "/settings/theme?theme=light", "", "").status == 302
    assert request(c.outsider, "POST", "/family", %{"family" => %{"name" => ""}}).status == 422

    assert request(c.outsider, "POST", "/family", %{
             "family" => %{"name" => "Bad CSRF"},
             "authenticity_token" => "invalid"
           }).status == 422

    assert footprint() == before
    System.put_env("SELF_HOSTED", "false")
    assert_settings(c.owner, c.outsider)

    assert request(c.owner, "POST", "/posters", %{"poster" => %{"name" => "Native Cloud"}}).status ==
             302

    assert request(c.owner, "GET", "/family").status == 200

    for {type, base} <- [
          {"track", "/tracks/99103/share_link"},
          {"timeline", "/share_links/timeline"}
        ] do
      assert request(actor, "GET", base <> "/new").status == 200
      assert request(actor, "POST", base, Shares.params(type)).status == 302
    end

    assert request(actor, "GET", "/share_links/hub").status == 200
    public = request(actor, "GET", "/s/" <> Shares.id(1))
    assert public.status in [200, 401]
    assert request(actor, "HEAD", "/s/" <> Shares.id(1)).status == public.status
    assert request(actor, "HEAD", "/s/" <> Shares.id(1)).resp_body == ""

    Repo.query!(
      "UPDATE shared_links SET magic_phrase='mounted-public-phrase' WHERE id=$1::text::uuid",
      [Shares.id(1)]
    )

    assert request(actor, "POST", "/s/" <> Shares.id(1) <> "/unlock", %{"phrase" => "wrong"}).status ==
             401

    unlocked =
      request(actor, "POST", "/s/" <> Shares.id(1) <> "/unlock", %{
        "phrase" => "mounted-public-phrase"
      })

    assert unlocked.status == 302
    assert Map.has_key?(unlocked.resp_cookies, "shared_link_" <> Shares.id(1))

    Repo.query!("UPDATE shared_links SET settings=$1 WHERE id=$2::text::uuid", [
      %{"audience" => "family", "family_id" => -1},
      Shares.id(1)
    ])

    assert request(actor, "GET", "/s/" <> Shares.id(1)).status == 404

    denied =
      request(actor, "POST", "/s/" <> Shares.id(1) <> "/unlock", %{
        "phrase" => "mounted-public-phrase"
      })

    assert denied.status == 404
    refute Map.has_key?(denied.resp_cookies, "shared_link_" <> Shares.id(1))
  end

  defp assert_demo_flow(user) do
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    session = RailsUser.session(user.id)
    path = "/settings/onboarding/demo_data"
    imported = browser_request(session, :post, path, %{})
    assert imported.status == 302
    [landing] = get_resp_header(imported, "location")
    assert URI.parse(landing).path == "/map/v2"
    assert URI.decode_query(URI.parse(landing).query)["panel"] == "timeline"

    assert Repo.query!(
             "SELECT count(*) FROM points WHERE user_id=$1 AND import_id IN (SELECT id FROM imports WHERE user_id=$1 AND demo=true)",
             [user.id]
           ).rows == [[17988]]

    live = Dawarich.Test.DemoData.real_point(user.id, 1_650_000_000)
    map = browser_request(session, :get, "/map/v2", %{})
    assert map.status == 200
    html = LazyHTML.from_document(map.resp_body)
    banner = LazyHTML.query(html, "#demo-data-banner")
    assert LazyHTML.text(banner) =~ "viewing demo data"
    form = LazyHTML.query(banner, "form")
    assert LazyHTML.attribute(form, "method") == ["post"]
    assert LazyHTML.attribute(form, "action") == [path]
    assert String.trim(LazyHTML.text(LazyHTML.query(form, "button"))) == "Delete"

    fields =
      for input <- LazyHTML.query(form, "input"),
          into: %{},
          do: {hd(LazyHTML.attribute(input, "name")), hd(LazyHTML.attribute(input, "value"))}

    assert fields["_method"] == "delete"
    assert is_binary(fields["authenticity_token"]) and fields["authenticity_token"] != ""

    denied =
      browser_request(session, :post, path, Map.put(fields, "authenticity_token", "invalid"))

    assert denied.status == 422

    assert Repo.query!("SELECT count(*) FROM imports WHERE user_id=$1 AND demo=true", [user.id]).rows ==
             [[1]]

    removed = browser_request(session, :post, path, fields)
    assert removed.status == 302
    assert get_resp_header(removed, "location") == ["http://www.example.com/"]

    assert removed.private.dawarich_rails_session_changes["flash"]["flashes"]["notice"] =~
             "removed"

    assert Repo.query!("SELECT id FROM points WHERE user_id=$1", [user.id]).rows == [[live]]

    assert Repo.query!("SELECT count(*) FROM imports WHERE user_id=$1 AND demo=true", [user.id]).rows ==
             [[0]]

    after_delete = browser_request(session, :get, "/map/v2", %{})
    assert after_delete.status == 200

    assert Enum.empty?(
             LazyHTML.query(LazyHTML.from_document(after_delete.resp_body), "#demo-data-banner")
           )

    assert browser_request(session, :delete, path, %{}).status == 302
    assert commands() == []
  end

  defp browser_request(session, method, path, params) do
    body =
      if method == :get,
        do: "",
        else:
          Plug.Conn.Query.encode(
            Map.put_new(params, "authenticity_token", RailsCsrf.masked_token(session))
          )

    Phoenix.ConnTest.build_conn()
    |> Map.put(:remote_ip, Process.get(:h01_remote_ip))
    |> put_req_header("accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", to_string(byte_size(body)))
    |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(session))
    |> Phoenix.ConnTest.dispatch(Endpoint, method, path, body)
  end

  defp declarations do
    family = DawarichWeb.FamilyFormRoutes
    track = DawarichWeb.TrackShareActions
    timeline = DawarichWeb.TimelineShareActions

    [
      {"GET", "/family/invitations/new", family},
      {"POST", "/family", family},
      {"PATCH", "/family", family},
      {"PUT", "/family", family},
      {"DELETE", "/family", family},
      {"POST", "/family/invitations", family},
      {"DELETE", "/family/invitations/synthetic-token", family},
      {"POST", "/family/memberships", family},
      {"DELETE", "/family/members/1", family},
      {"POST", "/family/location_requests", family},
      {"PATCH", "/family/location_requests/1/accept", family},
      {"PATCH", "/family/location_requests/1/decline", family},
      {"PATCH", "/family/location_sharing", family}
    ] ++
      for(
        {base, owner} <- [
          {"/tracks/99103/share_link", track},
          {"/share_links/timeline", timeline}
        ],
        {method, suffix} <- [
          {"GET", "/new"},
          {"POST", ""},
          {"DELETE", ""},
          {"PATCH", "/revoke"},
          {"POST", "/regenerate"},
          {"POST", "/regenerate_phrase"}
        ],
        do: {method, base <> suffix, owner}
      ) ++
      [
        {"POST", "/share_links/live/revoke", DawarichWeb.ShareManagementForm},
        {"POST", "/trips/1/share_link/revoke", DawarichWeb.ShareManagementForm},
        {"POST", "/share_links/shares/synthetic/revoke", DawarichWeb.ShareManagementForm},
        {"POST", "/posters", DawarichWeb.PostersController},
        {"DELETE", "/posters/1", DawarichWeb.PostersController},
        {"GET", "/achievements", Phoenix.LiveView.Plug},
        {"GET", "/settings/general", Phoenix.LiveView.Plug},
        {"GET", "/settings/integrations", Phoenix.LiveView.Plug},
        {"GET", "/admin/settings", Phoenix.LiveView.Plug},
        {"GET", "/trial/welcome", DawarichWeb.TrialWelcome},
        {"GET", "/", DawarichWeb.HomeDispatch},
        {"GET", "/notifications", Phoenix.LiveView.Plug}
      ] ++ settings_declarations()
  end

  defp settings_declarations do
    for {path, methods, plug} <- [
          {"/settings/general", ~w(POST PATCH PUT), DawarichWeb.SettingsActions},
          {"/settings/general/verify_supporter", ["POST"], DawarichWeb.SettingsSupporterActions},
          {"/settings/theme", ["GET"], DawarichWeb.SettingsMiscActions},
          {"/settings/changelog_consent", ~w(PATCH POST), DawarichWeb.SettingsMiscActions},
          {"/settings/generate_api_key", ["POST"], DawarichWeb.SettingsMiscActions},
          {"/settings/onboarding", ~w(POST PATCH PUT), DawarichWeb.OnboardingActions},
          {"/notifications/mark_as_read", ["POST"], DawarichWeb.NotificationActions},
          {"/notifications/destroy_all", ["POST"], DawarichWeb.NotificationActions},
          {"/notifications/1", ~w(DELETE POST), DawarichWeb.NotificationActions},
          {"/settings/general/test_email", ["POST"], DawarichWeb.TestEmail}
        ],
        method <- methods,
        do: {method, path, plug}
  end

  defp assert_settings(user, other) do
    for {method, params} <- [
          {"PATCH", %{"news_emails_enabled" => "false"}},
          {"PUT", %{"news_emails_enabled" => "true"}},
          {"POST", %{"_method" => "patch", "news_emails_enabled" => "false"}}
        ] do
      result = request(user, method, "/settings/general", params)
      assert result.status == 302
      assert get_resp_header(result, "location") == ["http://www.example.com/settings/general"]

      assert Dawarich.Accounts.settings(user.id)["news_emails_enabled"] ==
               (params["news_emails_enabled"] == "true")
    end

    assert request(user, "POST", "/settings/general/verify_supporter").status == 302
    get = request(user, "GET", "/settings/theme?theme=light")
    head = request(user, "HEAD", "/settings/theme?theme=light")
    assert get.status == 302
    assert head.status == get.status
    assert get_resp_header(head, "location") == get_resp_header(get, "location")
    assert head.resp_body == ""
    assert Dawarich.Accounts.get(user.id).theme == "light"

    for {method, params} <- [
          {"PATCH", %{"decision" => "granted"}},
          {"POST", %{"_method" => "patch", "decision" => "declined"}}
        ] do
      assert request(user, method, "/settings/changelog_consent", params).status == 302

      assert Dawarich.Accounts.get(user.id).changelog_consent ==
               if(params["decision"] == "granted", do: 1, else: 0)
    end

    old_key = Dawarich.Accounts.get(user.id).api_key
    cache_key = {DawarichWeb.RateLimit, old_key}
    Dawarich.TtlCache.fetch(cache_key, 60_000, fn -> :primed end)
    assert {:ok, :primed} = Dawarich.TtlCache.lookup(cache_key)
    other_key = Dawarich.Accounts.get(other.id).api_key

    Repo.query!(
      "UPDATE users SET provider='openid_connect', uid='h01-provider', otp_required_for_login=true WHERE id=$1",
      [user.id]
    )

    assert request(user, "POST", "/settings/generate_api_key", %{"user_id" => "#{other.id}"}).status ==
             302

    key = Dawarich.Accounts.get(user.id).api_key
    assert key != old_key
    assert byte_size(key) == 64
    assert Dawarich.TtlCache.lookup(cache_key) == :error
    assert Dawarich.Accounts.by_api_key(old_key) == nil
    assert Dawarich.Accounts.by_api_key(key).id == user.id
    assert Dawarich.Accounts.get(other.id).api_key == other_key

    for {method, params} <- [
          {"PATCH", %{}},
          {"PUT", %{}},
          {"POST", %{"_method" => "put"}}
        ] do
      result = request(user, method, "/settings/onboarding", params)
      assert result.status == 200
      assert result.resp_body == ""
      assert Dawarich.Accounts.settings(user.id)["onboarding_completed"]
    end

    own = Dawarich.Notifications.create!(Repo, user.id, :info, "Mounted notification", "Body")

    foreign =
      Dawarich.Notifications.create!(Repo, other.id, :info, "Foreign notification", "Body")

    assert request(user, "POST", "/notifications/mark_as_read").status == 303
    assert Dawarich.Notifications.get(user.id, own).read_at
    refute Dawarich.Notifications.get(other.id, foreign).read_at
    assert request(user, "DELETE", "/notifications/#{foreign}", %{"id" => "#{own}"}).status == 404
    assert Dawarich.Notifications.get(user.id, own)
    assert request(user, "DELETE", "/notifications/#{own}").status == 303
    own = Dawarich.Notifications.create!(Repo, user.id, :info, "Override notification", "Body")
    assert request(user, "POST", "/notifications/#{own}", %{"_method" => "delete"}).status == 303
    Dawarich.Notifications.create!(Repo, user.id, :info, "Delete all notification", "Body")
    assert request(user, "POST", "/notifications/destroy_all").status == 303
    assert Repo.query!("SELECT id FROM notifications WHERE user_id=$1", [user.id]).rows == []
    assert Dawarich.Notifications.get(other.id, foreign)
  end

  defp footprint do
    for table <-
          ~w(families family_memberships family_invitations family_location_requests shared_links posters job_outbox notifications imports points tracks trips visits places tags stats) do
      Repo.query!("SELECT row_to_json(t)::text FROM #{table} t ORDER BY row_to_json(t)::text").rows
    end ++
      Repo.query!("SELECT id, settings, theme, changelog_consent, api_key FROM users ORDER BY id").rows
  end

  defp request(user, method, path, params \\ %{}) do
    session = RailsUser.session(user.id)

    body =
      Plug.Conn.Query.encode(
        Map.put_new(params, "authenticity_token", RailsCsrf.masked_token(session))
      )

    raw_request(
      method,
      path,
      if(method in ~w(GET HEAD), do: "", else: body),
      RailsUser.cookie(session)
    )
  end

  defp raw_request(method, path, body, cookie) do
    Plug.Test.conn(method, path, body)
    |> Map.put(:remote_ip, Process.get(:h01_remote_ip))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", to_string(byte_size(body)))
    |> put_req_header("cookie", "_dawarich_session=" <> cookie)
    |> assign(:now, Shares.now())
    |> Endpoint.call(Endpoint.init([]))
  end
end
