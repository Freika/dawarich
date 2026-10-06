defmodule DawarichWeb.A12f2FClosureTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Accounts, RailsCookies, RailsSecret, Repo}
  alias Dawarich.Auth.{Account, Credentials}
  alias DawarichWeb.{AuthHandler, RailsAuth, RailsCsrf}

  @base "http://www.example.com"
  @hash Jason.decode!(File.read!("test/fixtures/auth/requests.json"))["user_before"][
          "encrypted_password"
        ]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    %{email: "closure-#{System.unique_integer([:positive])}@dawarich.test"}
  end

  @tag :a12f2_f_04
  test "Registration preserves self hosted and Cloud OIDC policy invitations field validation and source markup",
       ctx do
    assert Code.ensure_loaded?(DawarichWeb.AuthRegistration.Http)
    handler = DawarichWeb.AuthRegistration.Http

    opts = [
      enabled: true,
      context: %{self_hosted: true, oidc: false, registration_enabled: true},
      fallback: &replay/1
    ]

    form = apply(handler, :call, [request(:get, "/users/sign_up", %{}), opts])
    assert form.status == 200 and form.halted
    assert form.resp_body =~ ~s(action="/users")
    assert form.resp_body =~ "user[password_confirmation]"
    session = response_session(form)
    assert is_binary(session["_csrf_token"])

    params = %{
      "user[email]" => String.upcase(ctx.email),
      "user[password]" => "safepassword12",
      "user[password_confirmation]" => "safepassword12"
    }

    submitted = csrf(params, session, "POST", "/users")

    invalid =
      apply(handler, :call, [
        request(:post, "/users", session, Map.put(submitted, "authenticity_token", "invalid")),
        opts
      ])

    assert invalid.status == 422
    refute Repo.get_by(Account, email: ctx.email)
    created = apply(handler, :call, [request(:post, "/users", session, submitted), opts])
    assert created.status == 303
    user = Repo.get_by!(Account, email: ctx.email)
    assert user.status == 1 and user.plan == 1
    assert user.active_until.year == DateTime.utc_now().year + 1000
    assert byte_size(user.api_key) == 64
    assert Bcrypt.verify_pass("safepassword12", user.encrypted_password)
    signed = response_session(created)
    assert signed["session_id"] != session["session_id"]
    assert [[id], _] = signed["warden.user.user.key"]
    assert id == user.id
    refute Map.has_key?(signed, "_csrf_token")
    duplicate = apply(handler, :call, [request(:post, "/users", session, submitted), opts])
    assert duplicate.status == 422
    assert duplicate.resp_body =~ "already been taken"

    mismatch =
      Map.put(params, "user[password_confirmation]", "different")
      |> Map.put("user[email]", "other-" <> ctx.email)
      |> csrf(session, "POST", "/users")

    assert apply(handler, :call, [request(:post, "/users", session, mismatch), opts]).status ==
             422

    denied =
      Keyword.put(opts, :context, %{self_hosted: true, oidc: false, registration_enabled: false})

    denied_form = apply(handler, :call, [request(:get, "/users/sign_up", %{}), denied])
    assert denied_form.status == 302
    assert get_resp_header(denied_form, "location") == [@base <> "/"]

    for self_hosted <- [true, nil] do
      policy = Dawarich.Auth.RegistrationPolicy

      assert apply(policy, :allowed?, [
               %{self_hosted: self_hosted, oidc: false, registration_enabled: false},
               nil,
               ctx.email
             ]) == false

      assert apply(policy, :allowed?, [
               %{self_hosted: self_hosted, oidc: false, registration_enabled: false},
               %{email: ctx.email, acceptable: true},
               String.upcase(ctx.email)
             ])

      refute apply(policy, :allowed?, [
               %{self_hosted: self_hosted, oidc: true, registration_enabled: false},
               %{email: ctx.email, acceptable: true},
               ctx.email
             ])
    end

    assert apply(Dawarich.Auth.RegistrationPolicy, :allowed?, [
             %{self_hosted: false, oidc: true, registration_enabled: false},
             nil,
             ctx.email
           ])

    refute created.private[:replayed]
    now = DateTime.utc_now()

    [[family]] =
      Repo.query!(
        "INSERT INTO families(creator_id,name,created_at,updated_at) VALUES($1,'Synthetic family',$2,$2) RETURNING id",
        [id, DateTime.to_naive(now)],
        log: false
      ).rows

    token = "synthetic-invitation-#{id}"
    invited_email = "invited-" <> ctx.email

    Repo.query!(
      "INSERT INTO family_invitations(family_id,invited_by_id,email,token,expires_at,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$5,$5)",
      [family, id, invited_email, token, DateTime.to_naive(now)],
      log: false
    )

    invited_context = %{
      self_hosted: true,
      oidc: false,
      registration_enabled: false,
      clock: fn -> now end
    }

    invited_params =
      params
      |> Map.put("user[email]", invited_email)
      |> Map.put("user[invitation_token]", token)
      |> csrf(session, "POST", "/users")

    invited =
      handler.call(
        request(:post, "/users", session, invited_params),
        Keyword.put(opts, :context, invited_context)
      )

    assert invited.status == 303
    assert get_resp_header(invited, "location") == [@base <> "/family"]
    member = Repo.get_by!(Account, email: invited_email)

    assert [[1]] =
             Repo.query!("SELECT status FROM family_invitations WHERE token=$1", [token],
               log: false
             ).rows

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM family_memberships WHERE user_id=$1 AND family_id=$2",
               [member.id, family],
               log: false
             ).rows

    assert [[2]] =
             Repo.query!(
               "SELECT count(*) FROM notifications WHERE user_id IN ($1,$2)",
               [id, member.id],
               log: false
             ).rows
  end

  @tag :a12f2_f_02
  test "Credentials retain failure counters lockouts Cloud OIDC client addresses and source form responses",
       ctx do
    id = insert_user(ctx.email)

    context = %{
      native: true,
      ip: "192.0.2.10",
      log_rounds: 4,
      enqueue: fn intent ->
        send(self(), {:mail, intent.kind})
        :ok
      end
    }

    assert Credentials.login(ctx.email, "wrong", context) == {:error, :invalid}
    assert Repo.get!(Account, id).failed_attempts == 2
    Repo.query!("UPDATE users SET failed_attempts=9 WHERE id=$1", [id], log: false)
    assert Credentials.login(ctx.email, "safepassword12", context) == {:error, :invalid}
    locked = Repo.get!(Account, id)
    assert locked.failed_attempts == 11
    assert locked.locked_at != nil
    assert locked.unlock_token != nil
    assert_received {:mail, :unlock_instructions}
    assert Credentials.login(ctx.email, "safepassword12", context) == {:error, :invalid}
    assert Repo.get!(Account, id).failed_attempts == 13
    refute_received {:mail, _}

    Repo.query!(
      "UPDATE users SET locked_at=now()-interval '2 hours',failed_attempts=11 WHERE id=$1",
      [id],
      log: false
    )

    assert {:ok, _} = Credentials.login(ctx.email, "safepassword12", context)
    assert Repo.get!(Account, id).failed_attempts == 0
    session = guest()
    opts = [enabled: true, native: true, registration_enabled: true, fallback: &replay/1]
    System.delete_env("SELF_HOSTED")
    form = AuthHandler.call(request(:get, "/users/sign_in", %{}), opts)
    assert form.status == 200

    raw =
      csrf(
        %{
          "user[email]" => ctx.email,
          "user[password]" => "safepassword12",
          "user[remember_me]" => "1"
        },
        session,
        "POST",
        "/users/sign_in"
      )

    signed =
      request(:post, "/users/sign_in", session, raw)
      |> put_req_header("x-forwarded-for", "192.0.2.44")
      |> AuthHandler.call(opts)

    assert signed.status == 303
    assert response_session(signed)["session_id"] != session["session_id"]

    invalid =
      AuthHandler.call(
        request(:post, "/users/sign_in", session, Map.put(raw, "authenticity_token", "invalid")),
        opts
      )

    assert invalid.status == 422
    refute invalid.private[:replayed]
    assert Credentials.login("unknown-" <> ctx.email, "wrong", context) == {:error, :invalid}
  end

  @tag :a12f2_f_03
  test "Recovery owns legacy sessions tokens OIDC Cloud refusal and exact mail save failure ordering",
       ctx do
    alias Dawarich.Auth.Recovery.{Lifecycle, Token}
    alias DawarichWeb.AuthRecovery.Http
    id = insert_user(ctx.email)
    now = DateTime.utc_now()

    context = %{
      self_hosted: true,
      oidc: false,
      registration_enabled: true,
      secret: RailsSecret.fetch(),
      log_rounds: 4,
      clock: fn -> now end,
      sign_in_ip: "192.0.2.9",
      enqueue: fn notification ->
        send(self(), {:recovery, notification})
        :ok
      end
    }

    opts = [enabled: true, native: true, context: context, fallback: &replay/1]
    assert Http.route?(Plug.Test.conn(:patch, "/users/password"))
    session = guest()
    params = csrf(%{"user[email]" => ctx.email}, session, "POST", "/users/password")
    response = Http.call(request(:post, "/users/password", session, params), opts)
    assert response.status == 303
    assert_received {:recovery, notification}
    assert notification.user_id == id

    assert Repo.get!(Account, id).reset_password_token ==
             Token.digest(:reset_password_token, notification.raw, RailsSecret.fetch())

    raw = notification.raw

    Repo.query!(
      "UPDATE users SET reset_password_sent_at=$2,locked_at=$3,failed_attempts=11,failed_otp_attempts=10,otp_locked_at=$3 WHERE id=$1",
      [id, DateTime.to_naive(DateTime.add(now, -21_601)), DateTime.to_naive(now)],
      log: false
    )

    reset =
      csrf(
        %{
          "user[reset_password_token]" => raw,
          "user[password]" => "newpassword12345",
          "user[password_confirmation]" => "newpassword12345"
        },
        session,
        "PATCH",
        "/users/password"
      )

    expired = Http.call(request(:patch, "/users/password", session, reset), opts)
    assert expired.status == 422
    assert Repo.get!(Account, id).reset_password_token != nil

    Repo.query!(
      "UPDATE users SET reset_password_sent_at=$2 WHERE id=$1",
      [id, DateTime.to_naive(DateTime.add(now, -21_600))],
      log: false
    )

    completed = Http.call(request(:patch, "/users/password", session, reset), opts)
    assert completed.status == 303
    user = Repo.get!(Account, id)
    assert user.reset_password_token == nil
    assert user.locked_at == nil and user.otp_locked_at == nil
    assert user.failed_attempts == 0 and user.failed_otp_attempts == 0
    assert Bcrypt.verify_pass("newpassword12345", user.encrypted_password)
    assert [[^id], _] = response_session(completed)["warden.user.user.key"]
    replayed = Http.call(request(:patch, "/users/password", session, reset), opts)
    assert replayed.status == 422
    {:ok, issued} = Lifecycle.request_reset(ctx.email, context)
    digest = issued.user.reset_password_token

    failing =
      Keyword.put(opts, :context, %{context | enqueue: fn _ -> {:error, :unavailable} end})

    failure = Http.call(request(:post, "/users/password", session, params), failing)
    assert failure.status == 500
    assert Repo.get!(Account, id).reset_password_token == digest
    refute failure.private[:replayed]
  end

  @tag :a12f2_f_06
  test "Remember issuance restore expiry trackable Warden persistence and all device logout match Rails",
       ctx do
    alias DawarichWeb.AuthRestore
    id = insert_user(ctx.email)
    session = guest()
    opts = [enabled: true, native: true, registration_enabled: true, fallback: &replay/1]

    params =
      csrf(
        %{
          "user[email]" => ctx.email,
          "user[password]" => "safepassword12",
          "user[remember_me]" => "1"
        },
        session,
        "POST",
        "/users/sign_in"
      )

    login = AuthHandler.call(request(:post, "/users/sign_in", session, params), opts)
    assert login.status == 303
    cookie = login.resp_cookies["remember_user_token"].value
    assert login.resp_cookies["remember_user_token"].http_only
    assert login.resp_cookies["remember_user_token"].same_site == "Lax"

    assert {:ok, [[^id], _, _]} =
             RailsCookies.verify(
               cookie,
               "remember_user_token",
               RailsSecret.fetch(),
               DateTime.utc_now()
             )

    before = Repo.get!(Account, id).sign_in_count

    restored =
      Plug.Test.conn(:get, @base <> "/stats")
      |> put_req_header("cookie", "remember_user_token=" <> cookie)
      |> RailsAuth.call([])
      |> AuthRestore.call(enabled: true, native: true)

    assert [[^id], _] = response_session(restored)["warden.user.user.key"]
    assert Repo.get!(Account, id).sign_in_count == before + 1
    remembered = Repo.get!(Account, id).remember_created_at
    assert remembered != nil
    signout_session = response_session(restored) |> Map.put("_csrf_token", RailsCsrf.new_token())
    signout = csrf(%{}, signout_session, "DELETE", "/users/sign_out")
    logout = AuthHandler.call(request(:delete, "/users/sign_out", signout_session, signout), opts)
    assert logout.status == 303

    other_device =
      Plug.Test.conn(:get, @base <> "/stats")
      |> put_req_header("cookie", "remember_user_token=" <> cookie)
      |> RailsAuth.call([])

    assert other_device.assigns.current_user == nil
    assert Repo.get!(Account, id).remember_created_at == nil

    remembered_only =
      Plug.Test.conn(:delete, @base <> "/users/sign_out", URI.encode_query(signout))
      |> put_req_header("cookie", "remember_user_token=" <> cookie)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(URI.encode_query(signout))))

    assert AuthHandler.call(remembered_only, opts).status == 422
    assert Code.ensure_loaded?(Dawarich.Auth.Remember)

    assert apply(Dawarich.Auth.Remember, :valid?, [
             Repo.get!(Account, id),
             [
               [id],
               String.slice(@hash, 0, 29),
               Accounts.remember_generated_at(
                 DateTime.add(DateTime.utc_now(), -Accounts.remember_for())
               )
             ],
             DateTime.utc_now()
           ]) == false
  end

  @tag :a12f2_f_11
  test "API two factor Cloud setup confirm backup disable preserve source availability input errors encryption and consumption",
       ctx do
    alias Dawarich.Auth.TwoFactor.{Api, Totp}
    id = insert_user(ctx.email)
    unavailable = %{native: true, self_hosted: false, env: %{}}

    assert {:ok, 503, {:object, [{"error", "two_factor_not_available"}]}} =
             Api.run(:setup, id, %{"password" => "wrong"}, unavailable)

    crypto = Jason.decode!(File.read!("test/fixtures/active_record_encryption.json"))
    env = Enum.find(crypto["environments"], &(&1["name"] == "explicit keys"))["env"]

    context = %{
      native: true,
      self_hosted: false,
      env: env,
      backup_options: [log_rounds: 4],
      clock: fn -> ~U[2026-10-06 12:00:00.000000Z] end
    }

    assert {:ok, 401, _} = Api.run(:setup, id, %{"password" => "wrong"}, context)
    assert Repo.get!(Account, id).failed_attempts == 0

    assert {:ok, 200, {:object, setup}} =
             Api.run(:setup, id, %{"password" => "safepassword12"}, context)

    secret = List.keyfind(setup, "secret", 0) |> elem(1)
    refute Repo.get!(Account, id).otp_secret == secret
    code = Totp.at(secret, DateTime.to_unix(context.clock.()))

    assert {:ok, 200, {:object, [{"backup_codes", codes}]}} =
             Api.run(:confirm, id, %{"password" => "safepassword12", "otp_code" => code}, context)

    assert length(codes) == 10
    assert Repo.get!(Account, id).otp_required_for_login
    assert {:ok, 409, _} = Api.run(:setup, id, %{"password" => "safepassword12"}, context)

    assert {:ok, 200, _} =
             Api.run(
               :destroy,
               id,
               %{"password" => "safepassword12", "otp_code" => hd(codes)},
               context
             )

    user = Repo.get!(Account, id)
    refute user.otp_required_for_login
    assert user.otp_secret == nil and user.otp_backup_codes == []
  end

  @tag :a12f2_f_07
  test "Browser OTP and 2FA retain lockout backup consumption pending state remember and recovery effects",
       ctx do
    alias Dawarich.Auth.Otp.Pending
    alias Dawarich.Auth.TwoFactor.Secret
    alias DawarichWeb.AuthOtp.Http
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    id = insert_user(ctx.email)
    crypto = Jason.decode!(File.read!("test/fixtures/active_record_encryption.json"))
    env = Enum.find(crypto["environments"], &(&1["name"] == "explicit keys"))["env"]
    {:ok, secret} = Secret.encrypt("JBSWY3DPEHPK3PXP", env)

    Repo.query!(
      "UPDATE users SET otp_required_for_login=true,otp_secret=$2,failed_otp_attempts=6,settings='{}' WHERE id=$1",
      [id, secret],
      log: false
    )

    now = DateTime.utc_now()

    context = %{
      self_hosted: true,
      oidc: false,
      env: env,
      clock: fn -> now end,
      enqueue_otp_lock: fn actor ->
        send(self(), {:otp_lock, actor.id})
        :ok
      end
    }

    opts = [enabled: true, native: true, context: context, fallback: &replay/1]
    pending = Pending.start(guest(), id, "1", DateTime.to_unix(now))

    {last, _session} =
      Enum.reduce(1..5, {nil, pending}, fn n, {_response, session} ->
        params = csrf(%{"otp_attempt" => "invalid-code"}, session, "POST", "/users/otp_challenge")
        response = Http.call(request(:post, "/users/otp_challenge", session, params), opts)
        assert response.status == if(n < 5, do: 422, else: 302)
        refute response.private[:replayed]
        refute Map.has_key?(response.resp_cookies, "remember_user_token")
        assert response.resp_cookies["_dawarich_session"]
        {response, response_session(response)}
      end)

    ended = response_session(last)
    refute Map.has_key?(ended, "otp_user_id")

    expected =
      DawarichWeb.Translate.t(
        "en",
        "controllers.users.otp_challenge.account_temporarily_locked_due_to_too_many_failed_2fa_attempts",
        %{}
      )

    assert ended["flash"]["flashes"]["alert"] == expected
    assert Repo.get!(Account, id).failed_otp_attempts == 10
    assert Repo.get!(Account, id).otp_locked_at != nil
    assert_received {:otp_lock, ^id}
    refute_received {:otp_lock, _}
    key = "otp_lockout_email_throttle/user/#{id}"
    Dawarich.Redis.cache_command(["DEL", key])
    assert Code.ensure_loaded?(Dawarich.Auth.TwoFactor.Closure)

    Repo.query!(
      "UPDATE users SET otp_locked_at=NULL,failed_otp_attempts=0,provider='github',otp_secret=NULL,otp_required_for_login=false WHERE id=$1",
      [id],
      log: false
    )

    browser_context =
      Map.merge(context, %{
        self_hosted: false,
        oidc: true,
        native: true,
        backup_options: [log_rounds: 4]
      })

    browser_opts = [enabled: true, native: true, context: browser_context, fallback: &replay/1]
    actor = Repo.get!(Account, id)

    browser_session =
      Map.put(guest(), "warden.user.user.key", [
        [id],
        binary_part(actor.encrypted_password, 0, 29)
      ])

    browser = DawarichWeb.AuthTwoFactor.Http

    setup =
      browser.call(
        request(
          :post,
          "/settings/two_factor",
          browser_session,
          csrf(%{}, browser_session, "POST", "/settings/two_factor")
        ),
        browser_opts
      )

    assert setup.status == 200
    refute setup.private[:replayed]
    {:ok, otp} = Secret.decrypt(Repo.get!(Account, id).otp_secret, env)
    code = Dawarich.Auth.TwoFactor.Totp.at(otp, DateTime.to_unix(now))

    verified =
      browser.call(
        request(
          :post,
          "/settings/two_factor/verify",
          browser_session,
          csrf(%{"otp_attempt" => code}, browser_session, "POST", "/settings/two_factor/verify")
        ),
        browser_opts
      )

    assert verified.status == 200
    assert Repo.get!(Account, id).otp_required_for_login
    assert length(Repo.get!(Account, id).otp_backup_codes) == 10

    invalid =
      browser.call(
        request(:delete, "/settings/two_factor", browser_session, %{
          "password" => "safepassword12",
          "otp_attempt" => code,
          "authenticity_token" => "invalid"
        }),
        browser_opts
      )

    assert invalid.status == 422
    assert Repo.get!(Account, id).otp_required_for_login
  end

  @tag :a12f2_f_08
  test "Account and API key updates retain legacy sessions Cloud validation encryption and immediate token revocation",
       ctx do
    alias Dawarich.Auth.ApiKeys
    id = insert_user(ctx.email)
    old_key = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

    Repo.query!(
      "UPDATE users SET api_key=$2,provider='github',uid='synthetic-provider' WHERE id=$1",
      [id, old_key],
      log: false
    )

    context = %{native: true, self_hosted: false, oidc: true, log_rounds: 4}
    salt = String.slice(@hash, 0, 29)
    assert {:ok, rotated} = ApiKeys.rotate(id, salt, context)
    assert Accounts.by_api_key(old_key) == nil
    assert Accounts.by_api_key(rotated.api_key).id == id
    assert Repo.get!(Account, id).sign_in_count == 0
    assert Code.ensure_loaded?(Dawarich.Auth.AccountClosure)

    params = %{
      "email" => "changed-" <> ctx.email,
      "password" => "newpassword12345",
      "password_confirmation" => "newpassword12345"
    }

    assert {:ok, updated} =
             apply(Dawarich.Auth.AccountClosure, :update, [id, salt, params, context])

    assert updated.email == "changed-" <> ctx.email
    assert Bcrypt.verify_pass("newpassword12345", updated.encrypted_password)
    assert updated.sign_in_count == 0 and updated.failed_attempts == 0

    assert {:handoff, :session} =
             apply(Dawarich.Auth.AccountClosure, :update, [id, salt, params, context])

    Repo.query!("UPDATE users SET provider=NULL,uid=NULL WHERE id=$1", [id], log: false)
    new_salt = String.slice(updated.encrypted_password, 0, 29)

    assert {:error, %{errors: errors}} =
             apply(Dawarich.Auth.AccountClosure, :update, [
               id,
               new_salt,
               %{"current_password" => "wrong", "first_name" => "Changed"},
               context
             ])

    assert Enum.any?(errors, fn {field, _, _} -> field == :current_password end)
    assert Repo.get!(Account, id).failed_attempts == 0
  end

  @tag :a12f2_f_09
  test "Account destroy and confirmation preserve deployment rules family owner guards one use tokens and native deletion work",
       ctx do
    assert Code.ensure_loaded?(Dawarich.Auth.DestroyToken)
    alias Dawarich.Auth.{AccountDestroy, DestroyToken}
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    id = insert_user(ctx.email)

    context = %{
      self_hosted: true,
      env: %{},
      rails_secret: RailsSecret.fetch(),
      enqueue_destroy: fn actor ->
        send(self(), {:destroy, actor})
        :ok
      end
    }

    assert {:error, :password_required} =
             apply(AccountDestroy, :request, [id, %{"password" => "wrong"}, context])

    assert Repo.get!(Account, id).deleted_at == nil
    assert Repo.get!(Account, id).failed_attempts == 0
    {:ok, token} = apply(DestroyToken, :issue, [id, context])
    assert {:ok, claims} = apply(DestroyToken, :verify, [token, context])
    assert claims["purpose"] == "account_destroy"
    assert {:ok, :scheduled} = apply(AccountDestroy, :confirm, [token, context])
    assert_received {:destroy, ^id}
    assert Repo.get!(Account, id).deleted_at != nil
    assert {:error, :replayed} = apply(AccountDestroy, :confirm, [token, context])
    refute_received {:destroy, _}

    assert apply(DestroyToken, :verify, [token <> "tampered", context]) ==
             {:error, :invalid_token}

    key = "account_destroy:consumed:" <> claims["jti"]
    Dawarich.Redis.cache_command(["DEL", key])
  end

  @tag :a12f2_f_05
  test "Cloud signup retains pending payment trial checkout attribution locale invitation and accepted callbacks once",
       ctx do
    assert Code.ensure_loaded?(Dawarich.Auth.RegistrationSetup)
    alias Dawarich.Auth.{Registration, RegistrationSetup}
    jwt = System.get_env("JWT_SECRET_KEY")
    manager = System.get_env("MANAGER_URL")
    System.put_env("JWT_SECRET_KEY", "synthetic-signup-checkout-secret")
    System.put_env("MANAGER_URL", "https://manager.synthetic.test")

    on_exit(fn ->
      if jwt, do: System.put_env("JWT_SECRET_KEY", jwt), else: System.delete_env("JWT_SECRET_KEY")

      if manager,
        do: System.put_env("MANAGER_URL", manager),
        else: System.delete_env("MANAGER_URL")
    end)

    callbacks = %{
      webhook: fn id ->
        send(self(), {:signup_webhook, id})
        :ok
      end,
      partnero: fn id, key ->
        send(self(), {:partnero, id, key})
        :ok
      end
    }

    context = %{
      self_hosted: false,
      oidc: false,
      registration_enabled: false,
      callbacks: callbacks,
      chosen_locale: "de",
      locale: "de",
      log_rounds: 4
    }

    params = %{
      "email" => ctx.email,
      "password" => "safepassword12",
      "password_confirmation" => "safepassword12",
      "signup_intent" => "cloud"
    }

    {:ok, user} = Registration.create(params, context)

    session =
      Map.merge(guest(), %{
        "utm_source" => "synthetic",
        "gads_linker" => "linker value",
        "partnero_referral" => "synthetic-referral"
      })

    assert {:ok, result} = apply(RegistrationSetup, :complete, [user, params, session, context])
    assert result.user.status == 3
    assert result.location =~ "https://manager.synthetic.test/checkout?token="
    assert result.location =~ "&_gl=linker%20value"
    refute Map.has_key?(result.session, "warden.user.user.key")
    refute Map.has_key?(result.session, "utm_source")
    refute Map.has_key?(result.session, "partnero_referral")
    assert Accounts.settings(user.id)["locale"] == "de"
    assert Accounts.settings(user.id)["signup_intent"] == "cloud"
    assert_received {:signup_webhook, id}
    assert id == user.id
    assert_received {:partnero, ^id, "synthetic-referral"}
    assert {:error, %{errors: errors}} = Registration.create(params, context)
    assert Enum.any?(errors, fn {field, _, _} -> field == :email end)
    refute_received {:signup_webhook, _}
    [[source]] = Repo.query!("SELECT utm_source FROM users WHERE id=$1", [id], log: false).rows
    assert source == "synthetic"
  end

  @tag :a12f2_f_10
  test "Credential recovery account and remember cookies cross runtimes with source CSRF keys flags and terminal writes",
       ctx do
    alias Dawarich.Auth.SessionCookie
    incoming = %{"session_id" => nil, "_csrf_token" => nil, "locale" => "de"}
    {form, value} = SessionCookie.for_form(incoming, RailsSecret.fetch())
    assert is_binary(form["session_id"])
    assert is_binary(form["_csrf_token"])
    assert form["locale"] == "de"

    assert {:ok, ^form} =
             RailsCookies.decrypt(
               value,
               "_dawarich_session",
               RailsSecret.fetch(),
               DateTime.utc_now()
             )

    id = insert_user(ctx.email)
    user = Repo.get!(Account, id)

    {signed, signed_cookie} =
      SessionCookie.for_login(form, user, "Signed in", RailsSecret.fetch())

    assert signed["session_id"] != form["session_id"]
    refute Map.has_key?(signed, "_csrf_token")
    assert signed["locale"] == "de"

    assert {:ok, ^signed} =
             RailsCookies.decrypt(
               signed_cookie,
               "_dawarich_session",
               RailsSecret.fetch(),
               DateTime.utc_now()
             )

    salt = binary_part(user.encrypted_password, 0, 29)
    assert [[^id], ^salt] = signed["warden.user.user.key"]
    overflowing = Map.put(form, "large", String.duplicate("synthetic", 1000))

    assert_raise DawarichWeb.RailsSession.Overflow, fn ->
      SessionCookie.for_form(overflowing, RailsSecret.fetch())
    end
  end

  defp insert_user(email) do
    [[id]] =
      Repo.query!(
        "INSERT INTO users(email,encrypted_password,status,created_at,updated_at) VALUES($1,$2,1,now(),now()) RETURNING id",
        [email, @hash],
        log: false
      ).rows

    id
  end

  defp replay(conn), do: put_private(conn, :replayed, true)
  defp guest, do: %{"session_id" => "original-session", "_csrf_token" => RailsCsrf.new_token()}

  defp csrf(params, session, _method, _path),
    do: Map.put(params, "authenticity_token", RailsCsrf.masked_token(session))

  defp request(method, path, session, params \\ %{}) do
    raw = URI.encode_query(params)
    conn = Plug.Test.conn(method, @base <> path, raw)

    conn =
      if method == :get,
        do: conn,
        else:
          conn
          |> put_req_header("content-type", "application/x-www-form-urlencoded")
          |> put_req_header("content-length", Integer.to_string(byte_size(raw)))

    conn
    |> put_req_header(
      "cookie",
      "_dawarich_session=" <>
        RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())
    )
    |> put_req_header("origin", @base)
  end

  defp response_session(conn) do
    {:ok, session} =
      RailsCookies.decrypt(
        conn.resp_cookies["_dawarich_session"].value,
        "_dawarich_session",
        RailsSecret.fetch(),
        DateTime.utc_now()
      )

    session
  end
end
