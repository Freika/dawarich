defmodule DawarichWeb.AuthApiKeys.HttpTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Accounts, RailsCookies, Repo}
  alias Dawarich.Auth.SessionCookie
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{AuthApiKeys.Http, RailsCsrf}

  @secret "a11rest-key-http-synthetic-secret"
  @id 74001
  @path "/settings/generate_api_key"
  @turbo "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"

  defmodule CountingRepo do
    defdelegate one(query), to: Dawarich.Repo
    defdelegate query!(query, params, opts), to: Dawarich.Repo

    def update!(changeset, opts) do
      send(self(), :key_write)
      Dawarich.Repo.update!(changeset, opts)
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    previous = Map.new(~w(SELF_HOSTED APPLICATION_PROTOCOL RAILS_ENV), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("APPLICATION_PROTOCOL", "http")
    System.put_env("RAILS_ENV", "test")

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    hash = Bcrypt.hash_pwd_salt("a11rest-key-http-password", log_rounds: 4)

    RailsUser.insert!(%{
      id: @id,
      email: "a11rest-key-http@dawarich.test",
      encrypted_password: hash,
      api_key: "A11REST_KEY_HTTP",
      settings: %{}
    })

    {session, _} = SessionCookie.for_form(%{"retained" => true}, @secret)
    session = Map.put(session, "warden.user.user.key", [[@id], binary_part(hash, 0, 29)])
    owner = self()

    opts = [
      enabled: true,
      context: %{secret: @secret, self_hosted: true, oidc: false, repo: CountingRepo},
      fallback: fn conn ->
        raw =
          case conn.private[:dawarich_raw_body] do
            nil ->
              {:ok, raw, _} = read_body(conn)
              raw

            raw ->
              raw
          end

        send(owner, {:replayed, conn.method, raw})
        put_private(conn, :replayed, true)
      end
    ]

    %{session: session, opts: opts}
  end

  test "key rotation matches the Rails redirect and CSRF contract", c do
    assert Code.ensure_loaded?(Http), "key HTTP module must exist"

    for {accept, referer, body_token} <- [
          {"text/html", nil, false},
          {@turbo, "http://www.example.com/users/edit", false},
          {"text/html", "http://www.example.com/stats", true}
        ] do
      token = RailsCsrf.masked_token(c.session)
      body = if body_token, do: URI.encode_query(%{"authenticity_token" => token}), else: ""
      input = request(c.session, body) |> put_req_header("accept", accept)
      input = if body_token, do: input, else: put_req_header(input, "x-csrf-token", token)
      input = if referer, do: put_req_header(input, "referer", referer), else: input
      before = snapshot()
      result = Http.call(input, c.opts)
      assert result.status == 302 and result.halted
      assert get_resp_header(result, "location") == [referer || "http://www.example.com/"]
      assert get_resp_header(result, "x-dawarich-auth-owner") == ["native-api-keys"]
      assert get_resp_header(result, "x-frame-options") == ["SAMEORIGIN"]
      after_row = snapshot()
      assert after_row["api_key"] =~ ~r/\A[0-9a-f]{64}\z/
      assert after_row["api_key"] != before["api_key"]

      assert Map.drop(after_row, ~w(api_key updated_at)) ==
               Map.drop(before, ~w(api_key updated_at))

      assert result.assigns.rails_session == c.session
      assert result.resp_cookies == %{}
      refute result.resp_body =~ after_row["api_key"]
      assert_received :key_write
      refute_received :key_write
      refute_received {:replayed, _, _}
    end

    base =
      request(c.session, "") |> put_req_header("x-csrf-token", RailsCsrf.masked_token(c.session))

    invalid =
      [
        put_req_header(base, "referer", "https://foreign.dawarich.test/users/edit"),
        put_req_header(base, "referer", "/users/edit"),
        put_req_header(base, "referer", "http://user@www.example.com/users/edit"),
        put_req_header(base, "x-csrf-token", "bad"),
        delete_req_header(base, "x-csrf-token"),
        put_req_header(base, "origin", "https://foreign.dawarich.test"),
        put_req_header(base, "accept", "application/json"),
        put_req_header(base, "accept", "text/vnd.turbo-stream.html"),
        put_req_header(base, "x-http-method-override", "POST"),
        put_req_header(base, "x-dawarich-client", "mobile"),
        put_req_header(base, "x-forwarded-for", "127.0.0.2"),
        delete_req_header(base, "content-length"),
        put_req_header(base, "content-length", "65537"),
        put_req_header(base, "transfer-encoding", "chunked"),
        put_req_header(base, "content-type", "application/json"),
        request(%{}, ""),
        request(Map.put(c.session, "warden.user.user.key", [[@id], "stale"]), ""),
        request(Map.delete(c.session, "warden.user.user.key"), ""),
        request(Map.put(c.session, "pending_import_ticket", "special"), ""),
        request(c.session, "unknown=1"),
        request(c.session, "authenticity_token=bad&authenticity_token=bad"),
        request(c.session, "authenticity_token=%ZZ"),
        request(c.session, "_method=post"),
        request(c.session, "", "POST", @path <> "?locale=en"),
        request(c.session, "", "POST", "/settings/users/74001/regenerate_api_key")
      ] ++ Enum.map(~w(GET HEAD PUT PATCH DELETE), &request(c.session, "", &1))

    before = snapshot()

    for input <- invalid do
      result = Http.call(input, c.opts)
      assert result.private[:replayed] == true and result.halted
      assert_received {:replayed, method, raw}
      assert method == input.method
      assert raw == input.private[:original_body]
      assert snapshot() == before
      assert get_resp_header(result, "x-dawarich-auth-owner") == []
      assert result.resp_cookies == %{}
      refute_received :key_write
    end

    for context <- [
          %{secret: @secret, self_hosted: false, oidc: false},
          %{secret: @secret, self_hosted: true, oidc: true}
        ] do
      result = Http.call(base, Keyword.put(c.opts, :context, context))
      assert result.private[:replayed] == true
      assert_received {:replayed, _, ""}
      assert snapshot() == before
    end

    for sql <- [
          "provider='github'",
          "otp_required_for_login=true",
          "status=3",
          "locked_at=now()",
          "deleted_at=now()",
          "email=''",
          "settings='{ \"immich_url\":\"https://immich.dawarich.test/\"}'::jsonb"
        ] do
      Repo.query!("UPDATE users SET #{sql} WHERE id=$1", [@id])
      before = snapshot()
      result = Http.call(base, c.opts)
      assert result.private[:replayed] == true, sql
      assert_received {:replayed, _, ""}
      assert snapshot() == before
      refute_received :key_write

      Repo.query!(
        "UPDATE users SET provider=NULL, otp_required_for_login=false,status=1,
        locked_at=NULL,deleted_at=NULL,email='a11rest-key-http@dawarich.test',settings='{}'::jsonb WHERE id=$1",
        [@id]
      )
    end

    refute Http.route?(request(c.session, "", "GET"))
    refute Http.route?(request(c.session, "", "HEAD"))
    refute Http.route?(request(c.session, "", "POST", "/settings/users/74001/regenerate_api_key"))
  end

  test "legacy email rotations replay original bytes before writes using Rails outcomes", c do
    corpus = File.read!("test/fixtures/auth/account/api_keys.json") |> Jason.decode!()

    for {name, email, rotated} <- [
          {"legacy_uppercase_invalid_email", "INVALID", false},
          {"legacy_padded_valid_email", " A11REST-LEGACY-73507@DAWARICH.TEST ", true}
        ] do
      oracle = Enum.find(corpus, &(&1["name"] == name))
      assert oracle["status"] == 302
      assert oracle["key_changed"] == rotated
      assert oracle["reset_cleared"] == rotated
      old_status = if rotated, do: 401, else: 200

      assert oracle["lookups"] == [
               %{"query" => old_status, "bearer" => old_status},
               %{"query" => 200, "bearer" => 200}
             ]

      Repo.query!("UPDATE users SET email=$1 WHERE id=$2", [email, @id], log: false)
      before = snapshot()
      raw = URI.encode_query(%{"authenticity_token" => RailsCsrf.masked_token(c.session)})
      result = request(c.session, raw) |> Http.call(c.opts)
      assert result.private[:replayed] == true and result.halted
      assert_received {:replayed, "POST", ^raw}
      assert snapshot() == before
      refute_received :key_write
      assert result.resp_cookies == %{}
      assert get_resp_header(result, "x-dawarich-auth-owner") == []
      assert Accounts.by_api_key(before["api_key"]).id == @id

      for form <- [:query, :bearer] do
        conn = Plug.Test.conn("GET", "/api/v1/users/me") |> assign(:api_params, %{})

        conn =
          if form == :query,
            do: assign(conn, :api_params, %{"api_key" => before["api_key"]}),
            else: put_req_header(conn, "authorization", "Bearer " <> before["api_key"])

        assert DawarichWeb.Api.Auth.call(conn, []).assigns.api_user.id == @id
      end
    end
  end

  test "browser navigation rotation owns the Rails document POST and rejects other overrides",
       c do
    oracle =
      File.read!("test/fixtures/auth/account/api_keys.json")
      |> Jason.decode!()
      |> Enum.find(&(&1["name"] == "browser_navigation"))

    raw =
      String.replace(
        oracle["body"],
        "CSRF",
        URI.encode_www_form(RailsCsrf.masked_token(c.session))
      )

    input =
      request(c.session, raw)
      |> put_req_header("accept", oracle["accept"])
      |> put_req_header("referer", oracle["referer"])
      |> put_req_header("origin", "http://www.example.com")

    before = snapshot()
    result = Http.call(input, c.opts)
    assert result.status == oracle["status"] and result.halted
    assert get_resp_header(result, "location") == [oracle["location"]]
    assert get_resp_header(result, "x-dawarich-auth-owner") == ["native-api-keys"]
    after_row = snapshot()

    assert Enum.filter(Map.keys(before), &(before[&1] != after_row[&1])) |> Enum.sort() ==
             oracle["changed"]

    assert after_row["api_key"] =~ ~r/\A[0-9a-f]{64}\z/
    assert Accounts.by_api_key(before["api_key"]) == nil
    assert Accounts.by_api_key(after_row["api_key"]).id == @id
    assert result.assigns.rails_session == c.session
    assert result.resp_cookies == %{}
    assert_received :key_write
    refute_received :key_write
    refute_received {:replayed, _, _}

    for body <- [
          String.replace(raw, "_method=post", "_method=patch"),
          String.replace(raw, "_method=post", "_method=delete"),
          String.replace(raw, "_method=post", "_method=get"),
          String.replace(raw, "_method=post", "_method="),
          String.replace(raw, "_method=post", "_method=post%20"),
          raw <> "&_method=post",
          raw <> "&unknown=1",
          "_method=post&authenticity_token=bad"
        ] do
      result =
        request(c.session, body)
        |> put_req_header("accept", oracle["accept"])
        |> put_req_header("referer", oracle["referer"])
        |> Http.call(c.opts)

      assert result.private[:replayed] and result.halted
      assert_received {:replayed, "POST", ^body}
      assert snapshot() == after_row
      assert get_resp_header(result, "x-dawarich-auth-owner") == []
      refute_received :key_write
    end
  end

  defp request(session, body, method \\ "POST", path \\ @path) do
    Plug.Test.conn(method, "http://www.example.com" <> path, body)
    |> put_private(:original_body, body)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("accept", "text/html")
    |> Plug.Test.put_req_cookie(
      "_dawarich_session",
      RailsCookies.encrypt(session, "_dawarich_session", @secret)
    )
  end

  defp snapshot do
    [[row]] = Repo.query!("SELECT to_jsonb(users) FROM users WHERE id=$1", [@id], log: false).rows
    row
  end
end
