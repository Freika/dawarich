defmodule DawarichWeb.TripsGateEndpointTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log
  @endpoint DawarichWeb.Endpoint

  import Dawarich.Test.RawHTTP
  import Phoenix.ConnTest

  alias Dawarich.Test.{RailsUser, TripsSeeds}
  alias DawarichWeb.RailsCsrf

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)
    TripsSeeds.user!(8811)
    TripsSeeds.trip!(%{id: 881_101, user_id: 8811, path: [[12.37, 51.338], [12.381, 51.341]]})

    %{
      upstream: upstream,
      cookie: "_dawarich_session=" <> RailsUser.cookie(RailsUser.session(8811))
    }
  end

  defp serve do
    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    port
  end

  defp request(target, cookie),
    do: "GET #{target} HTTP/1.1\r\nHost: a\r\nCookie: #{cookie}\r\n\r\n"

  defp answered_by_puma(port, upstream, request) do
    client = connect(port)
    send_raw(client, request)
    puma = accept(upstream)
    {head, _rest} = read_head(puma)
    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npuma")
    assert {200, _headers, "puma"} = read_response(client)
    {request_line(head), header(head, "cookie")}
  end

  test "Phoenix answers the list for a signed-in user", ctx do
    client = connect(serve())
    send_raw(client, request("/trips", ctx.cookie))
    assert {200, _headers, body} = read_response(client)
    assert body =~ "data-phx-main"
  end

  test "a non-string page goes to Puma with the Rails cookie", ctx do
    assert {line, [cookie]} =
             answered_by_puma(serve(), ctx.upstream, request("/trips?page%5B%5D=2", ctx.cookie))

    assert line == "GET /trips?page%5B%5D=2 HTTP/1.1"
    assert "_dawarich_session=" <> _ = cookie
  end

  test "a gate that cannot read the database hands the request to Puma", ctx do
    port = serve()
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, :manual)

    assert {"GET /trips HTTP/1.1", [_cookie]} =
             answered_by_puma(port, ctx.upstream, request("/trips", ctx.cookie))
  end

  test "a page the read model rejects goes to Puma; the page before it stays with Phoenix", ctx do
    for n <- 1..6,
        do:
          TripsSeeds.trip!(%{
            id: 881_101 + n,
            user_id: 8811,
            path: [[12.37, 51.338], [12.381, 51.341]],
            started_at: NaiveDateTime.add(~N[2026-05-09 06:00:00], n * 86_400),
            ended_at: NaiveDateTime.add(~N[2026-05-12 20:00:00], n * 86_400)
          })

    TripsSeeds.trip!(%{
      id: 881_108,
      user_id: 8811,
      path: nil,
      started_at: ~N[2020-01-01 08:00:00],
      ended_at: ~N[2020-01-02 08:00:00]
    })

    Dawarich.Repo.query!("UPDATE trips SET visited_countries = '[1]'::jsonb WHERE id = 881108")

    port = serve()
    client = connect(port)
    send_raw(client, request("/trips", ctx.cookie))
    assert {200, _headers, body} = read_response(client)
    assert body =~ "data-phx-main"

    assert {line, [cookie]} =
             answered_by_puma(port, ctx.upstream, request("/trips?page=2", ctx.cookie))

    assert line == "GET /trips?page=2 HTTP/1.1"
    assert "_dawarich_session=" <> _ = cookie
  end

  test "a signed-in user whose timezone Rails would reject is answered by Puma", ctx do
    TripsSeeds.user!(8812, %{"timezone" => "Europe/Atlantis"})
    cookie = "_dawarich_session=" <> RailsUser.cookie(RailsUser.session(8812))

    assert {"GET /trips HTTP/1.1", [returned_cookie]} =
             answered_by_puma(serve(), ctx.upstream, request("/trips", cookie))

    assert "_dawarich_session=" <> _ = returned_cookie
  end

  test "Phoenix answers a trip it can render for a signed-in user", ctx do
    client = connect(serve())
    send_raw(client, request("/trips/881101", ctx.cookie))
    assert {200, _headers, body} = read_response(client)
    assert body =~ "data-phx-main"
  end

  test "a signed-out visitor is redirected to sign-in for a trip through the accepted id upper bound" do
    for target <- ~w(/trips/5 /trips/123456789012345678) do
      assert redirected_to(get(build_conn(), target), 302) ==
               "http://www.example.com/users/sign_in"
    end
  end

  test "an uncalculated, foreign or attachment-described trip goes to Puma with the Rails cookie",
       ctx do
    TripsSeeds.trip!(%{id: 881_102, user_id: 8811, path: nil})
    TripsSeeds.trip!(%{id: 881_103, user_id: 8811, path: [[12.37, 51.338], [12.381, 51.341]]})

    TripsSeeds.rich_text!(
      881_103,
      ~s(<action-text-attachment content-type="text/html" content="&lt;div&gt;source render error&lt;/div&gt;"></action-text-attachment>)
    )

    port = serve()

    for target <- ~w(/trips/881102 /trips/881103 /trips/881199) do
      assert {line, [cookie]} = answered_by_puma(port, ctx.upstream, request(target, ctx.cookie))
      assert line == "GET #{target} HTTP/1.1"
      assert "_dawarich_session=" <> _ = cookie
    end
  end

  test "note writes from the trip page reach Puma byte for byte and its Turbo Stream comes back unchanged",
       ctx do
    port = serve()
    accept = "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"
    session = RailsUser.session(8811)
    cookie = "_dawarich_session=" <> RailsUser.cookie(session)
    token = "authenticity_token=" <> URI.encode_www_form(RailsCsrf.masked_token(session))

    for {target, body} <- [
          {"/trips/881101/notes", token <> "&note%5Bdate%5D=2026-05-10&note%5Bbody%5D=Auensee"},
          {"/trips/881101/notes/7", "_method=patch&" <> token <> "&note%5Bbody%5D=Rosental"},
          {"/trips/881101/notes/7", "_method=delete&" <> token}
        ] do
      client = connect(port)

      send_raw(
        client,
        "POST #{target} HTTP/1.1\r\nHost: a\r\nCookie: #{cookie}\r\nAccept: #{accept}\r\nX-Dawarich-Client: legacy-web\r\n" <>
          "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: #{byte_size(body)}\r\n\r\n" <>
          body
      )

      puma = accept(ctx.upstream)
      {head, rest} = read_head(puma)
      assert request_line(head) == "POST #{target} HTTP/1.1"
      assert header(head, "accept") == [accept]
      assert header(head, "cookie") == [cookie]
      assert header(head, "content-type") == ["application/x-www-form-urlencoded"]
      assert read_at_least(puma, rest, byte_size(body)) == body

      stream =
        ~s(<turbo-stream action="replace" target="note-881101-2026-05-10"><template>x</template></turbo-stream>)

      reply(
        puma,
        "HTTP/1.1 200 OK\r\nContent-Type: text/vnd.turbo-stream.html; charset=utf-8\r\n" <>
          "Content-Length: #{byte_size(stream)}\r\n\r\n#{stream}"
      )

      assert {200, headers, ^stream} = read_response(client)
      assert values(headers, "content-type") == ["text/vnd.turbo-stream.html; charset=utf-8"]
    end
  end
end
