defmodule DawarichWeb.NativeOtpDocumentTest do
  use Dawarich.DataCase, async: false
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf
  @otp "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
  @keys ~w(otp_user_id otp_challenge_at otp_failed_attempts otp_remember_me)

  setup do
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

    env = %{
      "DAWARICH_RAILS" => "off",
      "SELF_HOSTED" => "true",
      "FORCE_SSL" => "false",
      "ALLOW_EMAIL_PASSWORD_LOGIN" => "true",
      "OTP_ENCRYPTION_PRIMARY_KEY" => "synthetic-primary",
      "OTP_ENCRYPTION_DETERMINISTIC_KEY" => "synthetic-deterministic",
      "OTP_ENCRYPTION_KEY_DERIVATION_SALT" => "synthetic-salt"
    }

    old = Map.new(env, fn {k, _} -> {k, System.get_env(k)} end)
    System.put_env(env)

    on_exit(fn ->
      for {k, v} <- old, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
    end)

    Dawarich.State.put_registration_enabled(Repo, true)
    {:ok, encrypted} = Dawarich.Auth.TwoFactor.Secret.encrypt(@otp, env)

    actor =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "native-otp@example.test",
        encrypted_password: Bcrypt.hash_pwd_salt("synthetic-password12", log_rounds: 4),
        otp_required_for_login: true,
        otp_secret: encrypted,
        api_key: "synthetic",
        settings: %{}
      })

    %{actor: actor, guest: %{"_csrf_token" => RailsCsrf.new_token(), "locale" => "de"}}
  end

  defp start(c) do
    fields = %{
      "user[email]" => c.actor.email,
      "user[password]" => "synthetic-password12",
      "user[remember_me]" => "1",
      "authenticity_token" => RailsCsrf.masked_form_token(c.guest, "/users/sign_in", "POST")
    }

    response =
      RailsFormRequests.post_form(c.guest, URI.encode_query(fields), [], "/users/sign_in")

    assert response.status == 422
    response
  end

  defp submit(session, code) do
    RailsFormRequests.post_form(
      session,
      URI.encode_query(%{
        "otp_attempt" => code,
        "authenticity_token" =>
          RailsCsrf.masked_form_token(session, "/users/otp_challenge", "POST")
      }),
      [],
      "/users/otp_challenge"
    )
  end

  test "POST OTP remains unauthenticated and shows no submitted code", c do
    response = start(c)
    assert response.resp_body =~ "/native/auth_http.js"
    refute response.resp_body =~ "achievement-unlocks"
    state = RailsFormRequests.rails_session(response)
    refute Map.has_key?(state, "warden.user.user.key")
    rejected = submit(state, "synthetic-rejected-code")
    refute rejected.resp_body =~ "synthetic-rejected-code"

    assert LazyHTML.attribute(
             LazyHTML.query(
               LazyHTML.from_document(rejected.resp_body),
               "input[name=otp_attempt]"
             ),
             "value"
           ) in [[], [""]]
  end

  test "repeated OTP failure renders native alert with unchanged pending counters", c do
    pending = RailsFormRequests.rails_session(start(c))

    for expected <- 1..2, reduce: pending do
      state ->
        failed = submit(state, "synthetic-rejected-code")
        assert failed.status == 422
        assert failed.resp_body =~ "/native/auth_http.js"

        assert Enum.count(
                 LazyHTML.query(
                   LazyHTML.from_document(failed.resp_body),
                   "[data-auth-error-summary]"
                 )
               ) == 1

        updated = RailsFormRequests.rails_session(failed)
        assert updated["otp_failed_attempts"] == expected
        assert updated["otp_user_id"] == c.actor.id
        assert updated["otp_challenge_at"] == pending["otp_challenge_at"]
        assert Repo.get!(Dawarich.Auth.Account, c.actor.id).failed_otp_attempts == expected
        updated
    end
  end

  test "OTP completion preserves remember and clears pending keys", c do
    initial = start(c)
    assert initial.resp_body =~ "/native/auth_http.js"
    pending = RailsFormRequests.rails_session(initial)

    response =
      submit(pending, Dawarich.Auth.TwoFactor.Totp.at(@otp, DateTime.to_unix(DateTime.utc_now())))

    assert response.status == 302
    state = RailsFormRequests.rails_session(response)
    assert hd(hd(state["warden.user.user.key"])) == c.actor.id
    refute Enum.any?(@keys, &Map.has_key?(state, &1))
    assert response.resp_cookies["remember_user_token"].http_only
  end

  test "every native cookie sign-in clears all four Rails pending OTP keys", c do
    pending =
      Map.merge(c.guest, %{
        "otp_user_id" => c.actor.id,
        "otp_challenge_at" => DateTime.to_unix(DateTime.utc_now()),
        "otp_failed_attempts" => 2,
        "otp_remember_me" => true
      })

    secret = Dawarich.RailsSecret.fetch()

    for encode <- [
          fn -> Dawarich.Auth.SessionCookie.for_login(pending, c.actor, "Signed in", secret) end,
          fn ->
            Dawarich.Auth.SessionCookie.for_otp_login(pending, c.actor, "Signed in", secret)
          end,
          fn ->
            Dawarich.Auth.SessionCookie.for_account_link(
              pending,
              c.actor,
              :sign_in,
              "Signed in",
              secret
            )
          end,
          fn -> Dawarich.Auth.SessionCookie.for_restore(pending, c.actor, secret) end
        ] do
      {state, cookie} = encode.()
      assert state["warden.user.user.key"] |> hd() |> hd() == c.actor.id
      refute Enum.any?(@keys, &Map.has_key?(state, &1))

      assert {:ok, ^state} =
               Dawarich.RailsCookies.decrypt(
                 cookie,
                 "_dawarich_session",
                 secret,
                 DateTime.utc_now()
               )
    end
  end

  test "initial challenge locale follows the approved display contract", c do
    response = start(c)
    assert response.resp_body =~ ~s(<html lang="de")

    assert Dawarich.Test.NativeAuthHTTP.text(response.resp_body, "h1") ==
             DawarichWeb.AuthOtp.Form.title("de")

    assert RailsFormRequests.rails_session(response)["locale"] == "de"
  end
end
