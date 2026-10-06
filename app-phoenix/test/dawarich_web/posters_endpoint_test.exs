defmodule DawarichWeb.PostersEndpointTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Posters.Persistence
  alias Dawarich.Test.{FrameSeeds, RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint

  setup do
    user = FrameSeeds.user!(97101, %{"locale" => "en", "timezone" => "UTC"})
    %{user: user, session: RailsUser.session(user.id)}
  end

  @tag mutation: "prepend"
  test "create prepends exact gallery card and flash or returns Rails HTML redirect", ctx do
    assert %{plug: DawarichWeb.PostersController} = route("POST", "/posters")
    conn = request(ctx.session, :post, "/posters", "poster[name]=Leipzig&poster[title]=")
    assert conn.status == 200
    assert conn.resp_body =~ ~s(action="prepend" target="poster-gallery-list")
    assert conn.resp_body =~ ~s(action="append" target="flash-messages")
    assert conn.resp_body =~ "Poster generation started. This takes about a minute."
    assert conn.resp_cookies == %{}
    assert [[id, "Leipzig", 0, %{"title" => ""}]] = rows(ctx.user.id)
    assert conn.resp_body =~ ~s(id="poster_#{id}")
    assert [["posters.created", %{"poster_id" => ^id}]] = commands()
    html = request(ctx.session, :post, "/posters", "poster[name]=Other", "text/html")
    assert html.status == 302
    assert get_resp_header(html, "location") == ["http://www.example.com/map/v2"]

    assert RailsFormRequests.rails_session(html)["flash"]["flashes"] ==
             %{"notice" => "Poster generation started. This takes about a minute."}
  end

  @tag mutation: "error"
  test "create error keeps Rails 422 contract without committing", ctx do
    assert %{plug: DawarichWeb.PostersController} = route("POST", "/posters")

    for accept <- ["text/vnd.turbo-stream.html", "text/html"] do
      conn = request(ctx.session, :post, "/posters", "", accept)
      assert conn.status == 422

      if accept == "text/html" do
        assert get_resp_header(conn, "location") == ["http://www.example.com/map/v2"]

        assert RailsFormRequests.rails_session(conn)["flash"]["flashes"] ==
                 %{"alert" => "Failed to start poster generation."}
      else
        assert conn.resp_body =~ "Failed to start poster generation."
        assert conn.resp_body =~ ~s(data-removals-timeout-value="0")
      end

      assert rows(ctx.user.id) == []
      assert commands() == []
    end

    Repo.query!("DROP TABLE phoenix.rails_commands")
    conn = request(ctx.session, :post, "/posters", "poster[name]=Atomic")
    assert conn.status == 422
    assert rows(ctx.user.id) == []
  end

  @tag mutation: "owner"
  test "delete scopes owner removes card and preserves HTML 303", ctx do
    assert %{plug: DawarichWeb.PostersController} = route("DELETE", "/posters/1")
    foreign = FrameSeeds.user!(97102)
    {:ok, id} = Persistence.create(%{}, foreign, "en")
    assert {:error, :missing} = Persistence.delete(id, ctx.user)
    assert request(ctx.session, :delete, "/posters/#{id}", "").status == 404
    assert length(rows(foreign.id)) == 1

    for accept <- ["text/vnd.turbo-stream.html", "text/html"] do
      {:ok, id} = Persistence.create(%{}, ctx.user, "en")
      attach(id)
      conn = request(ctx.session, :delete, "/posters/#{id}", "", accept)
      assert rows(ctx.user.id) == []

      assert Repo.query!(
               "SELECT id FROM active_storage_attachments WHERE record_type='Poster' AND record_id=$1",
               [id]
             ).rows == []

      assert Enum.any?(commands(), fn [kind, payload] ->
               kind == "posters.purge" and payload["poster_id"] == id and
                 length(payload["blob_ids"]) == 1
             end)

      if accept == "text/html" do
        assert conn.status == 303
        assert get_resp_header(conn, "location") == ["http://www.example.com/map/v2"]

        assert RailsFormRequests.rails_session(conn)["flash"]["flashes"] == %{
                 "notice" => "Poster deleted."
               }
      else
        assert conn.status == 200

        assert conn.resp_body ==
                 ~s(<turbo-stream action="remove" target="poster_#{id}"></turbo-stream>)
      end
    end
  end

  @tag mutation: "key"
  test "posters key and unsupported formats replay before writes", ctx do
    assert %{plug: DawarichWeb.PostersController} = route("POST", "/posters")
    upstream = RailsFormRequests.upstream!()
    saved = Application.get_env(:dawarich, :rails_routes, [])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, saved) end)

    for {key, body, accept} <- [
          {[], "poster[name]=Untouched&_method=delete", "text/html"},
          {["posters"], "poster[name]=Untouched", "text/html"}
        ] do
      Application.put_env(:dawarich, :rails_routes, key)

      {{line, forwarded}, conn} =
        RailsFormRequests.forwarded(upstream, fn ->
          request(ctx.session, :post, "/posters", body, accept)
        end)

      assert line == "POST /posters HTTP/1.1"
      assert forwarded =~ body
      assert conn.status == 204
      assert rows(ctx.user.id) == []
    end
  end

  @tag mutation: "get"
  test "poster GET and old preview route remain Rails fallback", ctx do
    upstream = RailsFormRequests.upstream!()

    for path <- ["/posters", "/posters/preview"] do
      assert route("GET", path) == :error

      {{line, ""}, conn} =
        RailsFormRequests.forwarded(upstream, fn ->
          request(ctx.session, :get, path, "", "text/html")
        end)

      assert line == "GET #{path} HTTP/1.1"
      assert conn.status == 204
    end
  end

  defp attach(poster) do
    stamp = NaiveDateTime.utc_now()

    {1, [%{id: blob}]} =
      Repo.insert_all(
        "active_storage_blobs",
        [
          %{
            key: "a9-#{poster}",
            filename: "poster.png",
            service_name: "local",
            byte_size: 1,
            created_at: stamp
          }
        ],
        returning: [:id]
      )

    Repo.insert_all("active_storage_attachments", [
      %{record_type: "Poster", record_id: poster, name: "image", blob_id: blob, created_at: stamp}
    ])
  end

  defp rows(user),
    do:
      Repo.query!("SELECT id,name,status,settings FROM posters WHERE user_id=$1 ORDER BY id", [
        user
      ]).rows

  defp route(verb, path),
    do: Phoenix.Router.route_info(DawarichWeb.Router, verb, path, "www.example.com")

  defp request(session, verb, path, body, accept \\ "text/vnd.turbo-stream.html") do
    body =
      if verb == :get,
        do: body,
        else:
          "authenticity_token=" <>
            URI.encode_www_form(RailsCsrf.masked_token(session)) <> "&" <> body

    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("accept", accept)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", to_string(byte_size(body)))
    |> dispatch(@endpoint, verb, path, body)
  end
end
