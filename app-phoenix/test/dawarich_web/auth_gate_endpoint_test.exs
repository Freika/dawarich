defmodule DawarichWeb.AuthGateEndpointTest do
  use Dawarich.IngestCase, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP

  alias Dawarich.{RailsCookies, RailsSecret, Redis}
  alias DawarichWeb.RailsCsrf

  @fixture Jason.decode!(File.read!(Path.expand("../fixtures/auth/activation.json", __DIR__)))
  @hash Jason.decode!(File.read!(Path.expand("../fixtures/auth/requests.json", __DIR__)))[
          "user_before"
        ]["encrypted_password"]
  @key "dawarich/registration_enabled"

  setup do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
    start_supervised!(hd(Redis.cache_child_specs()))
    {:ok, _} = Redis.cache_command(["DEL", @key])
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, nil)
      Application.delete_env(:dawarich, :phoenix_auth)

      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    %{port: port, upstream: upstream}
  end

  defp registration(name),
    do:
      {:ok, "OK"} =
        Redis.cache_command(["SET", @key, Base.decode64!(@fixture["registration"][name])])

  defp guest do
    session = %{"session_id" => "a11a-guest", "_csrf_token" => RailsCsrf.new_token()}

    {session,
     "_dawarich_session=" <>
       RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())}
  end

  defp get(path), do: "GET #{path} HTTP/1.1\r\nHost: a\r\n\r\n"

  defp form(method, path, cookie, body, extra \\ "") do
    "#{method} #{path} HTTP/1.1\r\nHost: a\r\nCookie: #{cookie}\r\n#{extra}" <>
      "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}"
  end

  defp exchange(ctx, request) do
    client = connect(ctx.port)
    send_raw(client, request)
    read_response(client)
  end

  defp to_puma(ctx, request) do
    client = connect(ctx.port)
    send_raw(client, request)
    puma = accept(ctx.upstream)
    {head, rest} = read_head(puma)
    length = head |> header("content-length") |> List.first("0") |> String.to_integer()
    body = binary_part(read_at_least(puma, rest, length), 0, length)
    reply(puma, "HTTP/1.1 200 OK\r\nSet-Cookie: rails=1; path=/\r\nContent-Length: 4\r\n\r\npuma")
    {status, headers, answer} = read_response(client)

    %{
      line: request_line(head),
      cookie: header(head, "cookie"),
      body: body,
      response:
        {status, values(headers, "set-cookie"), values(headers, "x-dawarich-auth-owner"), answer}
    }
  end

  defp no_puma(ctx), do: assert({:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 200))

  test "every flow is off by default: auth requests reach Puma byte for byte", ctx do
    {_session, cookie} = guest()
    body = "authenticity_token=x&user%5Bemail%5D=a%40dawarich.test&user%5Bpassword%5D=p"

    for {method, path} <- [
          {"POST", "/users/sign_in"},
          {"POST", "/users/sign_out"},
          {"POST", "/users/password"},
          {"PUT", "/users/password"},
          {"POST", "/users/unlock"}
        ] do
      seen = to_puma(ctx, form(method, path, cookie, body))
      assert seen.line == "#{method} #{path} HTTP/1.1"
      assert seen.cookie == [cookie]
      assert seen.body == body
      assert seen.response == {200, ["rails=1; path=/"], [], "puma"}
    end

    for path <-
          ~w(/users/sign_in /users/password/new /users/password/edit /users/unlock/new /users/unlock),
        do: assert(to_puma(ctx, get(path)).line == "GET #{path} HTTP/1.1")
  end

  test "credentials on: Phoenix answers the sign-in form with Rails' sign-up link rule", ctx do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    registration("false")

    assert {200, headers, body} = exchange(ctx, get("/users/sign_in"))
    assert values(headers, "x-dawarich-auth-owner") == ["native-credentials"]
    assert body =~ ~s(action="/users/sign_in")
    refute body =~ ~s(href="/users/sign_up")
    no_puma(ctx)

    registration("true")
    assert {200, _headers, body} = exchange(ctx, get("/users/sign_in"))
    assert body =~ ~s(href="/users/sign_up")
  end

  test "credentials on: a correct password signs in through Phoenix", ctx do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    registration("false")
    email = "a11a-#{System.unique_integer([:positive])}@dawarich.test"
    id = user!(%{email: email, encrypted_password: @hash})
    {session, cookie} = guest()

    body =
      URI.encode_query([
        {"authenticity_token", RailsCsrf.masked_token(session)},
        {"user[email]", email},
        {"user[password]", "safepassword12"},
        {"user[remember_me]", "0"}
      ])

    assert {303, headers, ""} = exchange(ctx, form("POST", "/users/sign_in", cookie, body))
    assert values(headers, "x-dawarich-auth-owner") == ["native-credentials"]
    assert values(headers, "location") == ["http://a/"]

    assert Enum.any?(
             values(headers, "set-cookie"),
             &String.starts_with?(&1, "_dawarich_session=")
           )

    assert Repo.query!("SELECT sign_in_count FROM users WHERE id = $1", [id]).rows == [[1]]
    no_puma(ctx)
  end

  test "credentials on: what Phoenix cannot serve reaches Puma with the request intact", ctx do
    Application.put_env(:dawarich, :phoenix_auth, ["credentials"])
    registration("false")
    {_session, cookie} = guest()

    body =
      "authenticity_token=forged&user%5Bemail%5D=a%40dawarich.test&user%5Bpassword%5D=p&user%5Bremember_me%5D=0"

    for extra <- ["", "X-Forwarded-For: 192.0.2.1\r\n"] do
      seen = to_puma(ctx, form("POST", "/users/sign_in", cookie, body, extra))
      assert seen.line == "POST /users/sign_in HTTP/1.1"
      assert seen.cookie == [cookie]
      assert seen.body == body
      assert seen.response == {200, ["rails=1; path=/"], [], "puma"}
    end

    {:ok, "OK"} = Redis.cache_command(["SET", @key, <<4, 8, ?T>>])
    assert to_puma(ctx, get("/users/sign_in")).line == "GET /users/sign_in HTTP/1.1"

    registration("false")
    System.put_env("SELF_HOSTED", "false")
    assert to_puma(ctx, get("/users/sign_in")).line == "GET /users/sign_in HTTP/1.1"
  end
end
