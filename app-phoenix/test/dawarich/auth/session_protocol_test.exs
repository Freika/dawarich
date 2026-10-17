defmodule Dawarich.Auth.SessionProtocolTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.{ActionCsrf, SessionCookie}
  alias Dawarich.RailsCookies

  @fixture Jason.decode!(File.read!(Path.expand("../../fixtures/auth/requests.json", __DIR__)))
  @guest @fixture["csrf_guest"]["decoded"]["session"]
  @secret "phoenix-a2-cookie-fixture-secret-not-for-production"
  @now ~U[2026-10-01 16:00:00Z]

  test "account-link protocol round-trips source pending and native completed session projections" do
    source = File.read!("test/fixtures/auth/account_link/requests.json") |> Jason.decode!()

    pending =
      Map.merge(source["challenge_en"]["session"], Map.take(@guest, ~w(session_id _csrf_token)))

    {form, cookie} = SessionCookie.for_form(pending, @secret)
    assert RailsCookies.decrypt(cookie, "_dawarich_session", @secret, @now) == {:ok, form}
    assert form["pending_oauth_link"] == pending["pending_oauth_link"]

    for action <- ~w(/auth/account_link/challenge /auth/account_link/email) do
      token = DawarichWeb.RailsCsrf.masked_form_token(form, action, "POST")
      assert ActionCsrf.valid?(form, token, "POST", action)
      refute ActionCsrf.valid?(form, token, "POST", "/users/sign_in")
    end

    rows =
      source["sequential_replay"] ++
        source["superseded_collision"] ++
        [source["transplant"]] ++ source["overlap"]["responses"] ++ [source["otp"]]

    for row <- rows do
      actor = row["before"]
      user = %{id: actor["id"], encrypted_password: actor["encrypted_password"]}
      kind = if actor["otp_required_for_login"], do: :link_only, else: :sign_in
      notice = row["session"]["flash"]["flashes"]["notice"]
      {completed, wire} = SessionCookie.for_account_link(form, user, kind, notice, @secret)
      assert RailsCookies.decrypt(wire, "_dawarich_session", @secret, @now) == {:ok, completed}

      assert Map.drop(completed, ~w(session_id _csrf_token warden.user.user.key)) ==
               Map.drop(row["session"], ~w(session_id _csrf_token warden.user.user.key))

      refute Map.has_key?(completed, "pending_oauth_link")
      refute Map.has_key?(completed, "pending_oauth_link_attempts")
      assert completed["_csrf_token"] == form["_csrf_token"]
      assert Map.has_key?(completed, "warden.user.user.key") == (kind == :sign_in)
    end
  end

  test "account-link cookies preserve source form link-only and default sign-in semantics" do
    source = File.read!("test/fixtures/auth/account_link/requests.json") |> Jason.decode!()
    actor = source["success_en"]["before"]
    user = %{id: actor["id"], encrypted_password: actor["encrypted_password"]}

    before =
      source["challenge_en"]["session"]
      |> Map.merge(Map.take(@guest, ~w(session_id _csrf_token)))
      |> Map.put("warden.user.user.session", %{"last_request_at" => 42})

    {form, cookie} = SessionCookie.for_form(before, @secret)
    assert form == before
    assert RailsCookies.decrypt(cookie, "_dawarich_session", @secret, @now) == {:ok, form}
    action = DawarichWeb.RailsCsrf.masked_form_token(form, "/auth/account_link/challenge", "POST")
    assert ActionCsrf.valid?(form, action, "POST", "/auth/account_link/challenge")

    for {kind, row} <- [{:sign_in, source["success_en"]}, {:link_only, source["otp"]}] do
      notice = row["session"]["flash"]["flashes"]["notice"]
      {completed, cookie} = SessionCookie.for_account_link(before, user, kind, notice, @secret)
      assert RailsCookies.decrypt(cookie, "_dawarich_session", @secret, @now) == {:ok, completed}
      refute Map.has_key?(completed, "pending_oauth_link")
      refute Map.has_key?(completed, "pending_oauth_link_attempts")

      for {key, retained} <- row["retained"] do
        assert completed[key] == before[key] == retained, key
      end

      assert completed["warden.user.user.session"] == before["warden.user.user.session"]
      assert completed["flash"] == row["session"]["flash"]

      if kind == :sign_in do
        assert completed["warden.user.user.key"] == [
                 [user.id],
                 binary_part(user.encrypted_password, 0, 29)
               ]
      else
        refute Map.has_key?(completed, "warden.user.user.key")
      end

      conn = Plug.Test.conn(:get, "/") |> DawarichWeb.AuthCookie.session({completed, cookie})
      flags = conn.resp_cookies["_dawarich_session"]
      assert flags[:path] == "/"
      assert flags[:http_only]
      assert flags[:same_site] == "Lax"
      assert flags[:secure] == DawarichWeb.ForceSSL.enabled?()
      refute Map.has_key?(conn.resp_cookies, "remember_user_token")

      assert_raise DawarichWeb.RailsSession.Overflow, fn ->
        SessionCookie.for_account_link(
          Map.put(before, "oversize", String.duplicate("x", 5000)),
          user,
          kind,
          notice,
          @secret
        )
      end
    end
  end

  test "web OTP protocol carries source pending and completed projections across runtimes" do
    alias Dawarich.Auth.Otp.Pending
    source = File.read!("test/fixtures/auth/otp/requests.json") |> Jason.decode!()
    row = source["start_en"]["session"]
    before = Map.merge(@guest, %{"locale" => "en", "otp_failed_attempts" => 3})
    pending = Pending.start(before, row["otp_user_id"], "1", row["otp_challenge_at"])
    assert Pending.valid(pending, row["otp_challenge_at"]) == {:ok, row["otp_user_id"], true}

    for key <- ~w(locale otp_user_id otp_challenge_at otp_remember_me otp_failed_attempts) do
      assert pending[key] == row[key], key
    end

    user = @fixture["login"]["user"]
    actor = %{id: user["id"], encrypted_password: user["encrypted_password"]}
    notice = source["totp_remember"]["session"]["flash"]["flashes"]["notice"]
    {completed, cookie} = SessionCookie.for_otp_login(pending, actor, notice, @secret)
    assert RailsCookies.decrypt(cookie, "_dawarich_session", @secret, @now) == {:ok, completed}

    for key <- ~w(otp_user_id otp_challenge_at otp_remember_me otp_failed_attempts) do
      refute Map.has_key?(completed, key)
    end

    assert completed["flash"] == source["totp_remember"]["session"]["flash"]
    assert completed["_csrf_token"] == pending["_csrf_token"]
  end

  test "OTP pending and completed cookies match source session and remember semantics" do
    alias Dawarich.Auth.{Otp.Pending, RememberCookie}
    source = File.read!("test/fixtures/auth/otp/requests.json") |> Jason.decode!()
    Code.ensure_loaded!(SessionCookie)
    assert function_exported?(SessionCookie, :for_otp_login, 4)
    user = @fixture["login"]["user"]
    user = %{id: user["id"], encrypted_password: user["encrypted_password"]}

    extra = %{
      "otp_failed_attempts" => 2,
      "locale" => "en",
      "user_return_to" => "/trips",
      "devise.synthetic" => "discarded",
      "warden.user.user.session" => %{"last_request_at" => 42}
    }

    before = Map.merge(@guest, extra)
    pending = Pending.start(before, user.id, "1", 1_791_115_200)
    {pending, pending_cookie} = SessionCookie.for_form(pending, @secret)
    anonymous = not Map.has_key?(pending, "warden.user.user.key")
    assert anonymous
    assert pending["session_id"] == before["session_id"]
    same_csrf = pending["_csrf_token"] == before["_csrf_token"]
    assert same_csrf

    pending_roundtrip =
      RailsCookies.decrypt(pending_cookie, "_dawarich_session", @secret, @now) == {:ok, pending}

    assert pending_roundtrip
    action = DawarichWeb.RailsCsrf.masked_form_token(pending, "/users/otp_challenge", "POST")
    assert ActionCsrf.valid?(pending, action, "POST", "/users/otp_challenge")
    refute ActionCsrf.valid?(pending, action, "POST", "/users/sign_in")

    notice = source["totp"]["session"]["flash"]["flashes"]["notice"]
    {completed, cookie} = SessionCookie.for_otp_login(pending, user, notice, @secret)

    completed_roundtrip =
      RailsCookies.decrypt(cookie, "_dawarich_session", @secret, @now) == {:ok, completed}

    assert completed_roundtrip

    assert Map.keys(completed) --
             ~w(session_id _csrf_token locale flash warden.user.user.key warden.user.user.session) ==
             []

    for {key, retained} <- source["totp"]["retained"] do
      matches = completed[key] == pending[key]
      assert matches == retained, key
    end

    identity =
      completed["warden.user.user.key"] == [
        [user.id],
        binary_part(user.encrypted_password, 0, 29)
      ]

    assert identity
    assert completed["warden.user.user.session"] == extra["warden.user.user.session"]
    assert completed["flash"] == source["totp"]["session"]["flash"]

    inherited =
      Map.put(pending, "flash", %{
        "discard" => ["alert"],
        "flashes" => %{"alert" => "discarded", "warning" => "retained"}
      })

    {flashed, _} = SessionCookie.for_otp_login(inherited, user, notice, @secret)
    assert flashed["flash"] == %{"discard" => [], "flashes" => %{"notice" => notice}}

    payload = [
      [user.id],
      binary_part(user.encrypted_password, 0, 29),
      Dawarich.Accounts.remember_generated_at(@now)
    ]

    remember =
      RememberCookie.sign(payload, @secret, DateTime.add(@now, Dawarich.Accounts.remember_for()))

    remembered =
      RailsCookies.verify(remember, "remember_user_token", @secret, @now) == {:ok, payload}

    assert remembered

    assert_raise DawarichWeb.RailsSession.Overflow, fn ->
      SessionCookie.for_otp_login(
        Map.put(pending, "oversize", String.duplicate("x", 5000)),
        user,
        notice,
        @secret
      )
    end
  end

  test "API auth protocol projects supported JWT and OTP state without issuing web sessions" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    config = Application.fetch_env!(:dawarich, :redis)
    conn = start_supervised!({Redix, {config[:url], [database: config[:cache_database]]}})

    env =
      Jason.decode!(File.read!("test/fixtures/active_record_encryption.json"))["environments"]
      |> Enum.find(&(&1["name"] == "explicit keys"))
      |> Map.fetch!("env")

    path =
      Path.join(System.tmp_dir!(), "a11f-protocol-#{System.unique_integer([:positive])}.json")

    refute File.exists?(path)

    context = %{
      env: Map.put(env, "JWT_SECRET_KEY", nil),
      rails_secret: @secret,
      cache_command: fn args -> Redix.command(conn, args) end
    }

    try do
      Dawarich.Auth.ApiProtocol.auth_write(path, context, "projection")
      payload = path |> File.read!() |> Jason.decode!()
      assert payload["mode"] == "api_auth" and payload["lifecycle"] == "projection"
      assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600

      assert Enum.map(payload["actors"], & &1["id"]) == [
               911_510_001,
               911_510_002,
               911_510_003,
               911_510_004
             ]

      refute Enum.any?(Map.keys(payload), &(&1 in ~w(sessions cookie remember form_token)))
      first = hd(payload["actors"])
      assert first["state"]["consumed_timestep"] == div(payload["at"], 30)
      assert first["state"]["failed_otp_attempts"] == 0
      assert Enum.all?(tl(payload["actors"]), &is_nil(&1["state"]["consumed_timestep"]))

      for actor <- payload["actors"] do
        [_, body, _] = String.split(actor["token"], ".")
        claims = body |> Base.url_decode64!(padding: false) |> Jason.decode!()
        assert claims["purpose"] == "otp_challenge"
        assert claims["user_id"] == actor["id"]
        assert claims["exp"] - claims["iat"] == 300
      end

      assert {:ok, marker} = Redix.command(conn, ["GET", hd(payload["marker_keys"])])
      assert is_binary(marker)

      assert Dawarich.Repo.query!(
               "SELECT id FROM users WHERE id=ANY($1)",
               [Enum.map(payload["actors"], & &1["id"])],
               log: false
             ).rows == []
    after
      if File.exists?(path) do
        payload = path |> File.read!() |> Jason.decode!()
        for key <- payload["marker_keys"], do: Redix.command(conn, ["DEL", key])
        File.rm!(path)
      end
    end
  end

  test "API management protocol preserves storage without issuing a session" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)

    path =
      Path.join(System.tmp_dir!(), "a4otp-protocol-#{System.unique_integer([:positive])}.json")

    refute File.exists?(path)

    env = %{
      "OTP_ENCRYPTION_PRIMARY_KEY" => "a4otp-synthetic-primary-not-for-production",
      "OTP_ENCRYPTION_DETERMINISTIC_KEY" => "a4otp-synthetic-deterministic-not-for-production",
      "OTP_ENCRYPTION_KEY_DERIVATION_SALT" => "a4otp-synthetic-salt-not-for-production"
    }

    File.write!(path, "", [:exclusive])
    File.chmod!(path, 0o600)

    try do
      Dawarich.Auth.ApiProtocol.write(path, env)
      payload = path |> File.read!() |> Jason.decode!()
      assert payload["mode"] == "api_two_factor_management"
      assert payload["schema"] == 1
      assert payload["summary"] == "API storage only; no session issued"
      assert length(payload["actors"]) == 3
      refute Enum.any?(Map.keys(payload), &(&1 in ~w(sessions cookie token remember form_token)))
      assert Enum.map(payload["actors"], & &1["id"]) == [954_801, 954_802, 954_803]
      assert Enum.all?(payload["actors"], &is_map(&1["disabled"]))
    after
      File.rm(path)
    end
  end

  test "management protocol retains Warden identity and Rails OTP consumption projections" do
    alias Dawarich.Auth.TwoFactor.{BackupCodes, Totp}
    corpus = File.read!("test/fixtures/auth/two_factor/requests.json") |> Jason.decode!()
    otp = File.read!("test/fixtures/auth/two_factor/otp.json") |> Jason.decode!()
    user = @fixture["login"]["user"]

    before =
      Map.merge(@guest, %{
        "user_return_to" => "/stats",
        "locale" => "en",
        "a11c" => "retain",
        "devise.test" => "retain",
        "warden.user.user.key" => [[user["id"]], binary_part(user["encrypted_password"], 0, 29)]
      })

    for row <- corpus, row["session_retained"] do
      {session, cookie} = SessionCookie.for_form(before, @secret)
      assert RailsCookies.decrypt(cookie, "_dawarich_session", @secret, @now) == {:ok, session}

      for {key, retained} <- row["session_retained"] do
        assert session[key] == before[key] == retained, row["name"] <> ":" <> key
      end

      assert session == before
      assert session["warden.user.user.key"] == before["warden.user.user.key"]
    end

    secret = Totp.generate_secret(Base.decode16!(otp["entropy_hex"], case: :lower))

    for vector <- otp["vectors"] do
      expected = if vector["valid"], do: {:ok, vector["result_timestep"]}, else: :invalid
      assert Totp.verify(secret, vector["code"], vector["at"], vector["consumed"]) == expected
    end

    {:ok, remaining} = BackupCodes.consume([user["encrypted_password"]], "safepassword12")
    assert remaining == []
    assert BackupCodes.consume(remaining, "safepassword12") == :invalid
  end

  test "account bypass rewrites the Warden salt with source session retention" do
    Code.ensure_loaded!(SessionCookie)
    assert function_exported?(SessionCookie, :for_account_update, 4)
    source = "test/fixtures/auth/account/requests.json" |> File.read!() |> Jason.decode!()
    oracle = Enum.find(source, &(&1["name"] == "both"))["session"]
    user = Map.take(@fixture["login"]["user"], ["id", "encrypted_password"])
    user = %{id: user["id"], encrypted_password: user["encrypted_password"]}

    before =
      Map.merge(@guest, %{
        "locale" => "en",
        "user_return_to" => "/stats",
        "a11rest" => "retain",
        "warden.user.user.key" => [[user.id], "old"],
        "warden.user.user.session" => %{"last_request_at" => 42},
        "devise.test" => "expire",
        "devise.oauth_data" => "expire",
        "flash" => %{"discard" => ["notice"], "flashes" => %{"notice" => "old"}}
      })

    notice = "Your account has been updated successfully."
    {updated, cookie} = SessionCookie.for_account_update(before, user, notice, @secret)
    {:ok, decoded} = RailsCookies.decrypt(cookie, "_dawarich_session", @secret, @now)
    compatible = decoded == updated
    assert compatible

    for {key, retained} <- oracle["retained"] do
      actual = updated[key] == before[key]
      assert actual == retained, key
    end

    warden_retained = updated["warden.user.user.key"] == before["warden.user.user.key"]
    assert warden_retained == oracle["warden_salt_retained"]

    salt_matches =
      updated["warden.user.user.key"] == [[user.id], binary_part(user.encrypted_password, 0, 29)]

    assert salt_matches == oracle["warden_matches_actor"]
    assert updated["warden.user.user.session"] == before["warden.user.user.session"]
    refute Map.has_key?(updated, "devise.test")
    refute Map.has_key?(updated, "devise.oauth_data")
    assert updated["flash"]["flashes"] == oracle["flash"]
    assert updated["flash"]["discard"] == []

    assert_raise DawarichWeb.RailsSession.Overflow, fn ->
      SessionCookie.for_account_update(
        Map.put(before, "a11rest", String.duplicate("x", 5_000)),
        user,
        notice,
        @secret
      )
    end
  end

  test "accepts actual Rails global and per-form tokens with action binding" do
    form = rails_token(@fixture["csrf_guest"]["form_token"])
    meta = rails_token(@fixture["csrf_guest"]["meta_token"])
    assert ActionCsrf.valid?(@guest, form, "POST", "/users/sign_in")
    assert ActionCsrf.valid?(@guest, meta, "POST", "/users/sign_in")
    refute ActionCsrf.valid?(@guest, form, "DELETE", "/users/sign_out")
    refute ActionCsrf.valid?(@guest, "invalid", "POST", "/users/sign_in")
  end

  test "login rotates the session, clears the old CSRF and emits legacy Warden credentials" do
    user = %{
      id: @fixture["login"]["user"]["id"],
      encrypted_password: @fixture["login"]["user"]["encrypted_password"]
    }

    before = Map.put(@guest, "user_return_to", "/stats")

    {after_login, cookie} =
      SessionCookie.for_login(before, user, "Signed in successfully.", @secret)

    assert {:ok, ^after_login} = RailsCookies.decrypt(cookie, "_dawarich_session", @secret, @now)
    assert after_login["session_id"] != before["session_id"]

    assert after_login["warden.user.user.key"] == [
             [user.id],
             binary_part(user.encrypted_password, 0, 29)
           ]

    refute Map.has_key?(after_login, "_csrf_token")
    refute Map.has_key?(after_login, "user_return_to")

    refute ActionCsrf.valid?(
             after_login,
             rails_token(@fixture["csrf_guest"]["form_token"]),
             "POST",
             "/users/sign_in"
           )

    assert after_login["flash"]["flashes"]["notice"] == "Signed in successfully."

    {restored, _cookie} = SessionCookie.for_restore(%{}, user, @secret)

    assert Enum.sort(Map.keys(restored)) ==
             Enum.sort(Map.keys(@fixture["remember_restore"]["decoded"]["session"]))

    assert restored["warden.user.user.key"] == after_login["warden.user.user.key"]
  end

  test "remember restoration renews the session but keeps the CSRF token, as Devise's rememberable does" do
    user = %{
      id: @fixture["login"]["user"]["id"],
      encrypted_password: @fixture["login"]["user"]["encrypted_password"]
    }

    {restored, _cookie} = SessionCookie.for_restore(@guest, user, @secret)
    assert restored["_csrf_token"] == @guest["_csrf_token"]
    refute restored["session_id"] == @guest["session_id"]

    assert ActionCsrf.valid?(
             restored,
             rails_token(@fixture["csrf_guest"]["form_token"]),
             "POST",
             "/users/sign_in"
           )
  end

  test "logout resets the whole session and form issuance renews CSRF afterward" do
    current =
      Map.merge(@guest, %{
        "locale" => "de",
        "warden.user.user.key" => [[7], "old"],
        "devise.oauth_data" => "old"
      })

    {logged_out, cookie} = SessionCookie.for_logout("Signed out successfully.", @secret)
    assert {:ok, ^logged_out} = RailsCookies.decrypt(cookie, "_dawarich_session", @secret, @now)
    refute Map.has_key?(logged_out, "warden.user.user.key")
    refute Map.has_key?(logged_out, "locale")
    assert logged_out["session_id"] != current["session_id"]
    {form_session, _cookie} = SessionCookie.for_form(logged_out, @secret)
    assert form_session["session_id"] == logged_out["session_id"]
    refute form_session["_csrf_token"] == current["_csrf_token"]
    assert is_binary(form_session["_csrf_token"])
  end

  defp rails_token(%{"one_time_pad" => pad, "xored" => xored}),
    do:
      Base.url_encode64(Base.decode16!(pad, case: :lower) <> Base.decode16!(xored, case: :lower),
        padding: false
      )
end
