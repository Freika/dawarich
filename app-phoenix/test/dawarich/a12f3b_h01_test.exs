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
    upstream = Application.get_env(:dawarich, :rails_upstream)
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    System.put_env("JWT_SECRET_KEY", "h01-synthetic-subscription-secret")
    Application.put_env(:dawarich, :rails_routes, [])
    Application.put_env(:dawarich, :rails_upstream, nil)

    on_exit(fn ->
      for {key, value} <- saved do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end

      Application.put_env(:dawarich, :rails_routes, routes)
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
    assert request(c.outsider, "POST", "/family", %{"family" => %{"name" => ""}}).status == 422

    assert request(c.outsider, "POST", "/family", %{
             "family" => %{"name" => "Bad CSRF"},
             "authenticity_token" => "invalid"
           }).status == 422

    assert footprint() == before
    System.put_env("SELF_HOSTED", "false")

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
      ]
  end

  defp footprint do
    for table <-
          ~w(families family_memberships family_invitations family_location_requests shared_links posters job_outbox notifications) do
      Repo.query!("SELECT row_to_json(t)::text FROM #{table} t ORDER BY row_to_json(t)::text").rows
    end
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
