defmodule DawarichWeb.ShareManagementEndpointTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  import Dawarich.Test.RawHTTP
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint

  setup do
    actor = FrameSeeds.seed_management!("hub_active_shared_en")
    %{actor: actor, session: RailsUser.session(actor.id)}
  end

  @tag mutation: "target"
  test "live and trip CRUD rotation responses match hub frame and HTML branches", ctx do
    for base <- ["/share_links/live", "/trips/99101/share_link"] do
      for {verb, suffix, notice} <- [
            {:post, "", "Share link created."},
            {:post, "/regenerate", "URL regenerated."},
            {:post, "/regenerate_phrase", "Magic phrase regenerated."},
            {:patch, "/revoke", "Share link revoked."}
          ] do
        prior = ids(ctx.actor.id)
        conn = request(ctx.session, verb, base <> suffix, "")
        assert conn.status == 302
        assert get_resp_header(conn, "location") == ["http://www.example.com" <> base <> "/new"]
        assert RailsFormRequests.rails_session(conn)["flash"]["flashes"] == %{"notice" => notice}
        if suffix == "/regenerate", do: refute(ids(ctx.actor.id) == prior)
      end

      created = request(ctx.session, :post, base, "hub=false")
      assert created.status == 200
      assert created.resp_cookies == %{}

      assert get_resp_header(created, "content-type") == [
               "text/vnd.turbo-stream.html; charset=utf-8"
             ]

      assert String.contains?(created.resp_body, ~s(action="update" target="share-hub-body"))

      assert String.contains?(
               created.resp_body,
               ~s(action="replace" target="live-share-indicator")
             )

      tab = if base == "/share_links/live", do: "live", else: ""
      assert String.contains?(created.resp_body, ~s(data-hub-tabs-active-value="#{tab}"))
      prior = ids(ctx.actor.id)
      deleted = request(ctx.session, :delete, base, "")
      assert deleted.status == 302
      assert length(ids(ctx.actor.id)) == length(prior) - 1
    end

    conn =
      request(
        ctx.session,
        :post,
        "/trips/99101/share_link",
        "shared_link%5Bexpires_at%5D=2020-01-01",
        [{"turbo-frame", "share-link-modal"}]
      )

    assert conn.status == 422
    assert conn.resp_body =~ ~s(<turbo-frame id="share-link-modal")
    refute conn.resp_body =~ "<!DOCTYPE html>"
  end

  @tag mutation: "csrf"
  test "invalid CSRF origin content type and method override replay byte intact before writes",
       ctx do
    assert %{plug: DawarichWeb.ShareManagementForm} =
             Phoenix.Router.route_info(
               DawarichWeb.Router,
               "POST",
               "/share_links/live",
               "www.example.com"
             )

    upstream = RailsFormRequests.upstream!()
    original = ids(ctx.actor.id)

    for {body, headers} <- [
          {"authenticity_token=wrong&shared_link%5Bname%5D=untouched", []},
          {token(ctx.session) <> "&shared_link[name]=untouched",
           [{"origin", "https://foreign.test"}]},
          {~s({"shared_link":{"name":"untouched"}}), [{"content-type", "application/json"}]},
          {token(ctx.session) <> "&_method=delete", []}
        ] do
      task = Task.async(fn -> raw(ctx.session, :post, "/share_links/live", body, headers) end)
      socket = accept(upstream)
      {head, rest} = read_head(socket)
      length = header(head, "content-length") |> hd() |> String.to_integer()
      assert read_at_least(socket, rest, length) == body
      reply(socket, "HTTP/1.1 204 No Content\r\n\r\n")
      assert Task.await(task).status == 204
      assert ids(ctx.actor.id) == original
      :gen_tcp.close(socket)
    end
  end

  @tag mutation: "key"
  test "share links and trip shares keys hand back every mutation", ctx do
    upstream = RailsFormRequests.upstream!()
    saved = Application.get_env(:dawarich, :rails_routes, [])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, saved) end)
    original = ids(ctx.actor.id)

    for {key, base} <- [
          {"share_links", "/share_links/live"},
          {"trip_shares", "/trips/99101/share_link"},
          {"trips", "/trips/99101/share_link"}
        ],
        {verb, suffix} <- [
          {:post, ""},
          {:delete, ""},
          {:patch, "/revoke"},
          {:post, "/regenerate"},
          {:post, "/regenerate_phrase"}
        ] do
      Application.put_env(:dawarich, :rails_routes, [key])

      assert %{plug: DawarichWeb.ShareManagementForm} =
               Phoenix.Router.route_info(
                 DawarichWeb.Router,
                 String.upcase(to_string(verb)),
                 base <> suffix,
                 "www.example.com"
               )

      {{line, _body}, conn} =
        RailsFormRequests.forwarded(upstream, fn ->
          request(ctx.session, verb, base <> suffix, "")
        end)

      assert line == String.upcase(to_string(verb)) <> " " <> base <> suffix <> " HTTP/1.1"
      assert conn.status == 204
      assert ids(ctx.actor.id) == original
    end

    Application.put_env(:dawarich, :rails_routes, ["share_links"])
    path = "/share_links/shares/a9f10000-0000-4000-8000-000000000001/revoke"

    {{_, _}, conn} =
      RailsFormRequests.forwarded(upstream, fn -> request(ctx.session, :patch, path, "hub=1") end)

    assert conn.status == 204
    assert ids(ctx.actor.id) == original
  end

  @tag mutation: "commit"
  test "committed mutation is never replayed when follow up response fails", ctx do
    assert %{plug: DawarichWeb.ShareManagementForm} =
             Phoenix.Router.route_info(
               DawarichWeb.Router,
               "POST",
               "/share_links/live",
               "www.example.com"
             )

    upstream = RailsFormRequests.upstream!()
    original = ids(ctx.actor.id)
    session = Map.put(ctx.session, "oversize", String.duplicate("a", 5000))

    task =
      Task.async(fn ->
        assert_raise DawarichWeb.RailsSession.Overflow, fn ->
          request(session, :post, "/share_links/live", "")
        end
      end)

    assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 100)
    Task.await(task)
    assert length(ids(ctx.actor.id)) == length(original) + 1
  end

  @tag mutation: "failed-live"
  test "invalid active live replacement is native and preserves rows and old stream revoked event",
       ctx do
    assert %{plug: DawarichWeb.ShareManagementForm} =
             Phoenix.Router.route_info(
               DawarichWeb.Router,
               "POST",
               "/share_links/live",
               "www.example.com"
             )

    old = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg, bus: false)
    on_exit(fn -> Application.put_env(:dawarich, :cable, old) end)
    original = Repo.query!("SELECT id::text,revoked_at FROM shared_links ORDER BY id").rows
    body = "shared_link[magic_phrase]=" <> String.duplicate("a", 256)
    conn = request(ctx.session, :post, "/share_links/live", body)
    assert conn.status == 422

    assert Repo.query!("SELECT id::text,revoked_at FROM shared_links ORDER BY id").rows ==
             original

    assert commands() == []

    assert Repo.query!("SELECT payload FROM phoenix.cable_events ORDER BY seq").rows
           |> Enum.map(fn [payload] -> Jason.decode!(payload) end) == [
             %{"revoked" => true},
             %{"revoked" => true}
           ]

    assert conn.resp_body =~ ~s(<turbo-frame id="share-link-modal")
  end

  @tag mutation: "nested"
  test "nested share forms preserve checkbox order and replay scalar map collisions", ctx do
    conn =
      request(
        ctx.session,
        :post,
        "/trips/99101/share_link",
        "shared_link[settings][show_stats]=0&shared_link[settings][show_stats]=1"
      )

    assert conn.status == 302

    assert [[true]] =
             Repo.query!(
               "SELECT (settings->>'show_stats')::boolean FROM shared_links WHERE user_id = $1 AND resource_type = 0 AND revoked_at IS NULL",
               [ctx.actor.id]
             ).rows

    upstream = RailsFormRequests.upstream!()

    for body <- [
          "shared_link=scalar&shared_link[name]=nested",
          "shared_link[name]=nested&shared_link=scalar",
          "shared_link[settings]=scalar&shared_link[settings][show_stats]=1"
        ] do
      {{_, forwarded}, conn} =
        RailsFormRequests.forwarded(upstream, fn ->
          request(ctx.session, :post, "/share_links/live", body)
        end)

      assert forwarded =~ body
      assert conn.status == 204
    end
  end

  @tag mutation: "broadcast-order"
  test "replacement follows Rails primary key order for old live broadcasts", ctx do
    saved = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg, bus: false)
    on_exit(fn -> Application.put_env(:dawarich, :cable, saved) end)

    fixture =
      "test/fixtures/share_management/hub_active_shared_en.json"
      |> File.read!()
      |> Jason.decode!()

    old =
      Enum.filter(
        fixture["before"],
        &(&1["user_id"] == ctx.actor.id and &1["resource_type"] == 3 and &1["expires_at"] == nil and
            &1["revoked_at"] == nil)
      )

    Repo.query!("DELETE FROM shared_links WHERE user_id = $1 AND resource_type = 3", [
      ctx.actor.id
    ])

    for row <- Enum.reverse(old), do: Dawarich.Test.ApiGolden.insert!("shared_links", row)
    assert request(ctx.session, :post, "/share_links/live", "").status == 302

    assert Repo.query!("SELECT channel FROM phoenix.cable_events ORDER BY seq").rows
           |> Enum.map(fn [stream] ->
             stream
             |> String.replace_prefix("shared_location:", "")
             |> Base.url_decode64!(padding: false)
             |> String.split("/")
             |> List.last()
           end) ==
             Enum.map(old, & &1["id"])
  end

  defp ids(user),
    do:
      Repo.query!("SELECT id::text FROM shared_links WHERE user_id = $1 ORDER BY id", [user]).rows

  defp token(session),
    do: "authenticity_token=" <> URI.encode_www_form(RailsCsrf.masked_token(session))

  defp request(session, verb, path, body, headers \\ []),
    do:
      raw(
        session,
        verb,
        path,
        token(session) <> if(body == "", do: "", else: "&" <> body),
        headers
      )

  defp raw(session, verb, path, body, headers) do
    conn =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", to_string(byte_size(body)))

    conn =
      Enum.reduce(headers, conn, fn {name, value}, conn -> put_req_header(conn, name, value) end)

    dispatch(conn, @endpoint, verb, path, body)
  end
end
