defmodule DawarichWeb.PlacesGateEndpointTest do
  use Dawarich.JobsCase, async: false

  @moduletag :capture_log
  @endpoint DawarichWeb.Endpoint

  import Dawarich.Test.RawHTTP
  import ExUnit.CaptureLog
  import Phoenix.ConnTest

  alias Dawarich.Test.FrameSeeds, as: S
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)
    user!(8421)
    for n <- 1..3, do: S.place!(8421, 842_100 + n, "Ort #{n}")

    %{upstream: upstream, cookie: cookie(8421)}
  end

  defp user!(id, settings \\ %{"timezone" => "Europe/Berlin"}),
    do: S.user!(id, settings, %{email: "a84-#{id}@example.invalid", api_key: "a84-k-#{id}"})

  defp cookie(id), do: "_dawarich_session=" <> RailsUser.cookie(RailsUser.session(id))

  defp serve do
    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    port
  end

  defp request(target, cookie, headers \\ []),
    do:
      "GET #{target} HTTP/1.1\r\nHost: a\r\nCookie: #{cookie}\r\n" <>
        Enum.map_join(headers, &"#{elem(&1, 0)}: #{elem(&1, 1)}\r\n") <> "\r\n"

  defp native(port, request) do
    client = connect(port)
    send_raw(client, request)
    read_response(client)
  end

  defp no_upstream(ctx), do: assert(:gen_tcp.accept(ctx.upstream.listen, 0) == {:error, :timeout})

  test "Phoenix answers the list for a signed-in user", ctx do
    client = connect(serve())
    send_raw(client, request("/places", ctx.cookie))
    assert {200, _headers, body} = read_response(client)
    assert body =~ "data-phx-main"
  end

  test "native nested page is refused in place without upstream", ctx do
    assert {200, _, body} = native(serve(), request("/places?page%5B%5D=2", ctx.cookie))
    assert body =~ "role=\"alert\""
    no_upstream(ctx)
  end

  test "native valueless scalar queries remain local", ctx do
    port = serve()

    for target <- ~w(/places?page /places?view /places?page=2&view),
        do: assert(match?({200, _, _}, native(port, request(target, ctx.cookie))))

    no_upstream(ctx)
  end

  test "native unsupported timezone renders a local alert", ctx do
    user!(8422, %{"timezone" => "Mars/Phobos"})
    S.place!(8422, 842_201, "Mars")
    assert {200, _, body} = native(serve(), request("/places", cookie(8422)))
    assert body =~ "role=\"alert\""
    no_upstream(ctx)
  end

  test "unavailable original actor admission stays typed and local", ctx do
    actor = %Dawarich.Accounts.User{id: Integer.pow(10, 100), encrypted_password: "synthetic"}

    assert Dawarich.Places.Access.admit(Dawarich.Accounts.Scope.for_user(actor, "en")) ==
             {:error, :unavailable}

    no_upstream(ctx)
  end

  test "native list formats and XHR remain locally owned", ctx do
    port = serve()

    for {target, headers, status} <- [
          {"/places.json", [], 406},
          {"/places?format=json", [], 406},
          {"/places", [{"X-Requested-With", "XMLHttpRequest"}], 200}
        ] do
      assert {^status, _, _} = native(port, request(target, ctx.cookie, headers))
    end

    no_upstream(ctx)
  end

  @frame [{"Accept", "text/html, application/xhtml+xml"}, {"Turbo-Frame", "place-drawer"}]

  test "Phoenix answers the drawer frame", ctx do
    client = connect(serve())
    send_raw(client, request("/places/842101", ctx.cookie, @frame))
    assert {302, headers, _body} = read_response(client)
    assert values(headers, "location") == ["http://a/map/v2?place_id=842101"]
    assert values(headers, "vary") == []
  end

  test "retained member client header refusal stays local", ctx do
    assert {302, _, _} =
             native(
               serve(),
               request("/places/842101", ctx.cookie, [hd(@frame), {"X-Dawarich-Client", "ios"}])
             )

    no_upstream(ctx)
  end

  test "unknown or repeated member frame headers never open a native dialog", ctx do
    port = serve()

    for {headers, expected} <- [
          {[hd(@frame), {"Turbo-Frame", "other"}], 302},
          {[hd(@frame), {"Turbo-Frame", "place-drawer"}, {"Turbo-Frame", "other"}], 302}
        ] do
      assert {status, _, body} = native(port, request("/places/842101", ctx.cookie, headers))
      assert status == expected
      refute body =~ "data-native-places"
    end

    no_upstream(ctx)
  end

  test "member extra scalar query remains standalone map-compatible", ctx do
    port = serve()

    for {target, headers} <- [
          {"/places/842101?locale=de", @frame},
          {"/places/842101?x=1", @frame}
        ] do
      assert {302, response_headers, _} = native(port, request(target, ctx.cookie, headers))
      assert values(response_headers, "location") == ["http://a/map/v2?place_id=842101"]
    end

    no_upstream(ctx)
  end

  test "foreign and missing member frames are locally unavailable", ctx do
    user!(8423)
    S.place!(8423, 842_301, "Fremd")
    port = serve()

    for target <- ~w(/places/842301 /places/842199) do
      assert {404, _, body} = native(port, request(target, ctx.cookie, @frame))
      refute body =~ "Fremd"
    end

    no_upstream(ctx)
  end

  test "drawer disappearance after admission is local and is never replayed", ctx do
    conn =
      build_conn(:get, "/places/842199")
      |> Plug.Conn.put_req_header("accept", "text/html")
      |> Map.put(:path_params, %{"id" => "842199"})
      |> Plug.Conn.assign(:rails_session, RailsUser.session(8421))
      |> Plug.Conn.assign(:current_user, Dawarich.Accounts.get(8421))
      |> Plug.Conn.assign(:locale, "en")

    log = capture_log(fn -> assert DawarichWeb.MapFrames.call(conn, :place).status == 422 end)
    refute log =~ "handed to Rails"
    no_upstream(ctx)
  end

  test "retained ids writes and nearby are refused or answered locally", ctx do
    S.place!(8421, 1_000_000_000_000_000_001, "Lang", advance: false)
    port = serve()

    for target <- ~w(/places/12abc /places/1000000000000000001 /places/842101/edit),
        do: assert(match?({404, _, _}, native(port, request(target, ctx.cookie, @frame))))

    assert {400, _, _} = native(port, request("/places/nearby?radius=0.5", ctx.cookie, @frame))

    before =
      Dawarich.Repo.query!("SELECT id,note FROM places WHERE user_id=8421 ORDER BY id", []).rows

    body = "_method=patch&place%5Bnote%5D=x"

    for {method, target} <- [
          {"POST", "/places"},
          {"PATCH", "/places/842101"},
          {"PUT", "/places/842101"},
          {"DELETE", "/places/842101"}
        ] do
      raw =
        "#{method} #{target} HTTP/1.1\r\nHost: a\r\nCookie: #{ctx.cookie}\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: #{byte_size(body)}\r\n\r\n" <>
          body

      assert {status, _, _} = native(port, raw)
      assert status in [403, 422]
    end

    assert Dawarich.Repo.query!("SELECT id,note FROM places WHERE user_id=8421 ORDER BY id", []).rows ==
             before

    no_upstream(ctx)
  end

  test "a signed-out frame request is redirected by Phoenix" do
    conn =
      Enum.reduce(@frame, build_conn(), fn {name, value}, conn ->
        Plug.Conn.put_req_header(conn, String.downcase(name), value)
      end)
      |> get("/places/842101")

    assert redirected_to(conn, 302) == "http://www.example.com/users/sign_in"

    [_, value] =
      Regex.run(
        ~r/_dawarich_session=([^;]+)/,
        conn |> Plug.Conn.get_resp_header("set-cookie") |> hd()
      )

    staged =
      build_conn()
      |> put_req_cookie("_dawarich_session", value)
      |> DawarichWeb.RailsAuth.call([])

    assert staged.assigns.rails_session["user_return_to"] == "/places/842101"
  end
end
