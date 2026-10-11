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

  defp native_response(ctx, port, target, status \\ 200, cookie \\ nil) do
    client = connect(port)
    send_raw(client, request(target, cookie || ctx.cookie))
    {actual, _headers, body} = read_response(client)
    assert actual == status
    assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
    body
  end

  test "Phoenix answers the list for a signed-in user", ctx do
    client = connect(serve())
    send_raw(client, request("/trips", ctx.cookie))
    assert {200, _headers, body} = read_response(client)
    assert body =~ "data-phx-main"
  end

  test "native nonstring trip page refuses in place without forwarding", ctx do
    body = native_response(ctx, serve(), "/trips?page%5B%5D=2")
    assert body =~ "data-native-trip-index-refused"
    refute body =~ "trip-881101"
  end

  test "native trip database failure refuses without forwarding", ctx do
    port = serve()
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, :manual)

    native_response(ctx, port, "/trips", 500)
  end

  test "native trip pages preserve bounded cards including source values the hybrid gate rejected",
       ctx do
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

    second = native_response(ctx, port, "/trips?page=2")
    doc = LazyHTML.from_document(second)

    assert LazyHTML.query(doc, "[data-trip-id]") |> LazyHTML.attribute("data-trip-id") == [
             "881101",
             "881108"
           ]

    assert second =~ "No points found"
    refute second =~ "data-native-trip-index-refused"
  end

  test "native invalid trip timezone uses the existing zone fallback without forwarding", ctx do
    TripsSeeds.user!(8812, %{"timezone" => "Europe/Atlantis"})
    cookie = "_dawarich_session=" <> RailsUser.cookie(RailsUser.session(8812))

    body = native_response(ctx, serve(), "/trips", 200, cookie)
    assert body =~ "id=\"native-trips-index\""
    assert body =~ "No trips yet"
    refute body =~ "data-native-trip-index-refused"
    refute body =~ "data-trip-id="

    previous = System.get_env("TIME_ZONE")
    System.put_env("TIME_ZONE", "Europe/Berlin")

    on_exit(fn ->
      if previous, do: System.put_env("TIME_ZONE", previous), else: System.delete_env("TIME_ZONE")
    end)

    TripsSeeds.trip!(%{
      id: 881_201,
      user_id: 8812,
      name: "Zone fallback trip",
      started_at: ~N[2026-05-09 23:30:00],
      ended_at: ~N[2026-05-10 01:00:00]
    })

    populated = native_response(ctx, serve(), "/trips", 200, cookie)
    card = LazyHTML.from_document(populated) |> LazyHTML.query("[data-trip-id='881201']")
    text = LazyHTML.text(card)
    assert text =~ "Zone fallback trip"
    assert text =~ "10 May 2026"
    refute text =~ "9 May 2026"
    refute populated =~ "trip-881101"
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

  test "native uncalculated attachment and foreign trip states remain owned without forwarding",
       ctx do
    TripsSeeds.trip!(%{id: 881_102, user_id: 8811, path: nil})
    TripsSeeds.trip!(%{id: 881_103, user_id: 8811, path: [[12.37, 51.338], [12.381, 51.341]]})

    TripsSeeds.rich_text!(
      881_103,
      ~s(<action-text-attachment content-type="text/html" content="&lt;div&gt;source render error&lt;/div&gt;"></action-text-attachment>)
    )

    port = serve()

    uncalculated = native_response(ctx, port, "/trips/881102")
    assert uncalculated =~ "id=\"trip-shell\""
    assert uncalculated =~ "data-trip-map-state=\"empty\""
    attachment = native_response(ctx, port, "/trips/881103")
    assert attachment =~ "role=\"alert\""
    refute attachment =~ "trip-shell"
    refute attachment =~ "source render error"
    refute attachment =~ "<action-text-attachment"
    foreign = TripsSeeds.user!(8813)
    TripsSeeds.trip!(%{id: 881_199, user_id: foreign.id, name: "Private foreign trip"})

    for target <- ~w(/trips/881199 /trips/881198) do
      body = native_response(ctx, port, target)
      assert body =~ "role=\"alert\""
      refute body =~ "trip-shell"
      refute body =~ "Private foreign trip"
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
