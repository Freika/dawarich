defmodule DawarichWeb.RailsSessionTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Dawarich.RailsCookies
  alias DawarichWeb.{ForceSSL, RailsCsrf, RailsSession}

  @fixture "test/fixtures/rails_session_writer.json" |> File.read!() |> Jason.decode!()
  @cookies_fixture "test/fixtures/rails_cookies.json" |> File.read!() |> Jason.decode!()
  @secret @fixture["rails_test_secret"]

  defp decrypt(value) do
    {:ok, session} =
      RailsCookies.decrypt(value, "_dawarich_session", @secret, DateTime.utc_now())

    session
  end

  defp attributes(line),
    do:
      line
      |> String.split(";")
      |> tl()
      |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
      |> Enum.sort()

  defp flash(notice), do: %{"flash" => %{"flashes" => %{"notice" => notice}, "discard" => []}}

  defp cookie_size(value),
    do: byte_size("_dawarich_session") + byte_size(URI.decode_www_form(value))

  defp fresh_cookie_size(changes) do
    changes
    |> Map.put("session_id", String.duplicate("0", 32))
    |> RailsCookies.encrypt("_dawarich_session", @secret)
    |> cookie_size()
  end

  defp envelope(value) do
    [data, iv, tag] =
      value |> URI.decode_www_form() |> String.split("--") |> Enum.map(&Base.decode64!/1)

    key =
      Plug.Crypto.KeyGenerator.generate(@secret, "authenticated encrypted cookie",
        iterations: 1000,
        length: 32,
        digest: :sha256
      )

    :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, data, "", tag, false)
  end

  defp inner_json(value),
    do:
      value |> envelope() |> Jason.decode!() |> get_in(["_rails", "message"]) |> Base.decode64!()

  defp put_env!(vars) do
    previous = Map.new(vars, fn {name, _value} -> {name, System.get_env(name)} end)
    on_exit(fn -> Enum.each(previous, &set_env/1) end)
    Enum.each(vars, &set_env/1)
  end

  defp set_env({name, nil}), do: System.delete_env(name)
  defp set_env({name, value}), do: System.put_env(name, value)

  test "a rewrite keeps every key Rails wrote and changes only the allowed ones" do
    before = decrypt(@fixture["session_cookie"])
    assert Map.has_key?(before, "warden.user.user.key")
    {:ok, value} = RailsSession.rewrite(@fixture["session_cookie"], %{"locale" => "de"}, @secret)
    assert decrypt(value) == Map.put(before, "locale", "de")

    {:ok, value} = RailsSession.rewrite(value, %{"locale" => nil}, @secret)
    assert decrypt(value) == before
  end

  @tag :identity_contract
  test "an absent or unreadable session gains an identity only for effective changes" do
    for cookie <- [nil, "not-a-rails-cookie", @cookies_fixture["other_purpose_cookie"]] do
      {:ok, value} = RailsSession.rewrite(cookie, %{"locale" => "de"}, @secret)
      session = decrypt(value)
      valid_identity = Regex.match?(~r/\A[0-9a-f]{32}\z/, session["session_id"] || "")
      assert valid_identity
      assert Map.delete(session, "session_id") == %{"locale" => "de"}

      for changes <- [
            %{},
            %{"locale" => nil, "flash" => nil, "_csrf_token" => nil, "user_return_to" => nil}
          ] do
        assert RailsSession.rewrite(cookie, changes, @secret) == :unchanged

        request = conn(:get, "/")

        request =
          if cookie, do: put_req_cookie(request, "_dawarich_session", cookie), else: request

        response = request |> RailsSession.stage(changes) |> send_resp(200, "")
        assert response.resp_cookies == %{}
        assert get_resp_header(response, "set-cookie") == []
      end
    end
  end

  test "nothing is written when nothing changed" do
    {:ok, value} = RailsSession.rewrite(@fixture["session_cookie"], %{"locale" => "de"}, @secret)
    assert RailsSession.rewrite(value, %{"locale" => "de"}, @secret) == :unchanged

    conn =
      conn(:get, "/")
      |> put_req_cookie("_dawarich_session", value)
      |> fetch_cookies()
      |> RailsSession.put(%{"locale" => "de"})

    assert conn.resp_cookies == %{}
  end

  test "two writes in one request keep both changes" do
    conn =
      conn(:get, "/")
      |> put_req_cookie("_dawarich_session", @fixture["session_cookie"])
      |> fetch_cookies()
      |> RailsSession.put(%{"locale" => "de"})
      |> RailsSession.put(%{"_csrf_token" => token = RailsCsrf.new_token()})

    assert decrypt(conn.resp_cookies["_dawarich_session"].value) ==
             Map.merge(decrypt(@fixture["session_cookie"]), %{
               "locale" => "de",
               "_csrf_token" => token
             })
  end

  test "only flash, _csrf_token, locale and user_return_to may be written, Warden's keys only deleted" do
    assert {:ok, _} = RailsSession.rewrite(nil, %{"user_return_to" => "/notifications"}, @secret)

    assert {:ok, _} =
             RailsSession.rewrite(
               @fixture["session_cookie"],
               %{"warden.user.user.key" => nil, "warden.user.user.session" => nil},
               @secret
             )

    assert_raise ArgumentError, fn ->
      RailsSession.rewrite(nil, %{"warden.user.user.key" => [[1], "x"]}, @secret)
    end

    assert_raise ArgumentError, fn -> RailsSession.rewrite(nil, %{"theme" => nil}, @secret) end
  end

  test "a changes argument that is not a map is refused without leaking the secret or the cookie" do
    cookie = @fixture["session_cookie"]
    conn = conn(:get, "/") |> put_req_cookie("_dawarich_session", cookie) |> fetch_cookies()

    for changes <- [[locale: "de"], nil] do
      {error, stacktrace} =
        try do
          RailsSession.put(conn, changes)
        rescue
          error -> {error, __STACKTRACE__}
        end

      assert %ArgumentError{} = error

      logged =
        Exception.format(:error, error, stacktrace) <> inspect(error) <> inspect(stacktrace)

      refute logged =~ @secret
      refute logged =~ cookie
    end
  end

  test "Phoenix writes the envelope layout Rails requires, message first" do
    {:ok, value} = RailsSession.rewrite(nil, %{"locale" => "de"}, @secret)

    assert envelope(value) =~
             ~r/\A\{"_rails":\{"message":"[A-Za-z0-9+\/]+=*","exp":null,"pur":"cookie\._dawarich_session"\}\}\z/
  end

  test "Phoenix escapes each character as Rails' cookie serializer does" do
    for [character, rails] <- @fixture["rails_cookie_json"] do
      phoenix = inner_json(RailsCookies.encrypt([character], "_dawarich_session", @secret))

      assert {byte_size(phoenix), String.downcase(phoenix)} ==
               {byte_size(rails), String.downcase(rails)}
    end
  end

  @tag :identity_contract
  test "the 4 KB decision matches Rails' on values Rails escapes" do
    %{"unit" => unit, "units" => units, "extra" => extra, "fits" => fits} = @fixture["overflow"]
    assert Enum.any?(Map.values(fits)) and not Enum.all?(Map.values(fits))

    for {count, rails} <- fits do
      notice = String.duplicate(unit, units) <> String.duplicate(extra, String.to_integer(count))

      changes = flash(notice)
      legacy_size = changes |> RailsCookies.encrypt("_dawarich_session", @secret) |> cookie_size()
      assert {count, legacy_size <= 4096} == {count, rails}
      expected_size = fresh_cookie_size(changes)
      assert expected_size > legacy_size

      phoenix =
        try do
          {:ok, written} = RailsSession.rewrite(nil, changes, @secret)
          assert cookie_size(written) == expected_size
          true
        rescue
          RailsSession.Overflow -> false
        end

      assert {count, phoenix} == {count, expected_size <= 4096}
    end
  end

  test "a session above 4 KB is refused, as Rails refuses it" do
    assert_raise RailsSession.Overflow, fn ->
      RailsSession.rewrite(nil, flash(String.duplicate("a", 4096)), @secret)
    end
  end

  @tag :identity_contract
  test "the 4 KB limit is Rails': the name plus the unescaped value, above 4096 bytes" do
    results =
      for length <- 2000..2400 do
        changes = flash(String.duplicate("a", length))
        size = fresh_cookie_size(changes)

        accepted =
          try do
            {:ok, written} = RailsSession.rewrite(nil, changes, @secret)
            assert cookie_size(written) == size
            true
          rescue
            RailsSession.Overflow -> false
          end

        {size, accepted}
      end

    assert Enum.all?(results, fn {size, accepted} -> accepted == size <= 4096 end)
    assert Enum.any?(results, &elem(&1, 1))
    refute Enum.all?(results, &elem(&1, 1))
  end

  test "a new CSRF token has the shape of the one Rails generates" do
    rails = @cookies_fixture["csrf"]["session_cookie"] |> decrypt() |> Map.fetch!("_csrf_token")
    token = RailsCsrf.new_token()

    assert byte_size(token) == byte_size(rails)
    assert {:ok, <<_::binary-size(32)>>} = Base.url_decode64(token, padding: false)
    refute token == RailsCsrf.new_token()
  end

  test "the cookie carries the attributes Rails gives it, with secure under force_ssl" do
    for {protocol, line} <- [
          {"http", @fixture["set_cookie"]},
          {"https", @fixture["force_ssl"]["set_cookie"]}
        ] do
      put_env!(%{"APPLICATION_PROTOCOL" => protocol, "RAILS_ENV" => "production"})

      conn =
        conn(:get, "/")
        |> fetch_cookies()
        |> RailsSession.put(%{"locale" => "de"})
        |> send_resp(200, "")

      [written] =
        for {"set-cookie", value} <- conn.resp_headers,
            String.starts_with?(value, "_dawarich_session="),
            do: value

      assert attributes(written) == attributes(line)
    end
  end

  test "force_ssl is on exactly where Rails turns it on, and a no-op elsewhere" do
    env = %{"APPLICATION_PROTOCOL" => "HTTPS", "RAILS_ENV" => "production"}
    assert ForceSSL.enabled?(env)
    assert ForceSSL.enabled?(%{"APPLICATION_PROTOCOL" => "https"})
    refute ForceSSL.enabled?(%{env | "RAILS_ENV" => "test"})
    refute ForceSSL.enabled?(%{env | "APPLICATION_PROTOCOL" => "http"})
    refute ForceSSL.enabled?(%{"RAILS_ENV" => "production"})

    plain = conn(:get, "http://dawarich.example/map") |> ForceSSL.call(ForceSSL.init([]))
    refute plain.halted
    assert get_resp_header(plain, "strict-transport-security") == []

    put_env!(%{"APPLICATION_PROTOCOL" => "https", "RAILS_ENV" => nil, "RACK_ENV" => "test"})
    refute ForceSSL.enabled?()
    put_env!(%{"RACK_ENV" => "production"})
    assert ForceSSL.enabled?()
  end

  describe "under force_ssl" do
    setup do
      put_env!(%{"APPLICATION_PROTOCOL" => "https", "RAILS_ENV" => "production"})
    end

    defp force(%{"method" => method, "url" => url, "headers" => headers}) do
      headers
      |> Enum.reduce(conn(method, url), fn {name, value}, conn ->
        put_req_header(conn, name, value)
      end)
      |> ForceSSL.call(ForceSSL.init([]))
    end

    defp answer(conn) do
      header = &List.first(get_resp_header(conn, &1))

      {if(conn.halted, do: conn.status, else: 200), header.("location"),
       header.("strict-transport-security"), header.("content-type")}
    end

    test "every request Rails recorded is redirected or let through with HSTS, as Rails does" do
      for request <- @fixture["force_ssl"]["requests"] do
        assert answer(force(request)) ==
                 {request["status"], request["location"], request["hsts"],
                  request["content_type"]},
               inspect(request)
      end
    end

    test "a request Rails treats as https continues as https" do
      conn =
        force(%{
          "method" => "GET",
          "url" => "http://dawarich.example/map",
          "headers" => %{"forwarded" => "proto=https"}
        })

      refute conn.halted
      assert {conn.scheme, conn.port} == {:https, 443}
    end

    test "repeated forwarding headers are read joined, as Puma hands them to Rack" do
      conn = conn(:get, "http://dawarich.example/map")

      conn = %{
        conn
        | req_headers:
            conn.req_headers ++ [{"x-forwarded-proto", "http"}, {"x-forwarded-proto", "https"}]
      }

      refute ForceSSL.call(conn, ForceSSL.init([])).halted
    end

    test "the redirect follows the Rails recorded forwarded host" do
      rails = @fixture["force_ssl"]["forwarded_host"]
      assert rails["location"] == "https://evil.example/map"

      assert answer(force(rails)) ==
               {rails["status"], rails["location"], nil, rails["content_type"]}
    end
  end
end
