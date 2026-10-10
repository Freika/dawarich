defmodule DawarichWeb.NativeAuthIntegrationTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint

  setup do
    Dawarich.Test.NativeAuthHTTP.isolate_counters()
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

    env = %{
      "DAWARICH_RAILS" => "off",
      "SELF_HOSTED" => "true",
      "FORCE_SSL" => "false",
      "ALLOW_EMAIL_PASSWORD_LOGIN" => "true",
      "JWT_SECRET_KEY" => "synthetic-integration-jwt",
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

    actor =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "native-integration@example.test",
        api_key: "synthetic",
        settings: %{"onboarding_completed" => true}
      })

    Dawarich.Test.NativeAuthHTTP.isolate_counters(actor.id)

    {:ok, encrypted} =
      Dawarich.Auth.TwoFactor.Secret.encrypt("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", env)

    otp =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "native-integration-otp@example.test",
        api_key: "synthetic",
        encrypted_password: Bcrypt.hash_pwd_salt("synthetic-password12", log_rounds: 4),
        otp_required_for_login: true,
        otp_secret: encrypted,
        settings: %{}
      })

    %{actor: actor, otp: otp, guest: %{"_csrf_token" => RailsCsrf.new_token()}}
  end

  defp fetch(session, path),
    do:
      build_conn() |> put_req_cookie("_dawarich_session", RailsUser.cookie(session)) |> get(path)

  defp submit(session, path, fields \\ %{}, headers \\ []) do
    Dawarich.Test.NativeAuthHTTP.post_form(
      session,
      URI.encode_query(
        Map.put(
          fields,
          "authenticity_token",
          RailsCsrf.masked_form_token(session, path, String.upcase(fields["_method"] || "post"))
        )
      ),
      headers,
      path
    )
  end

  defp assert_native(%{status: status} = response) when status in [302, 303] do
    assert get_resp_header(response, "x-dawarich-auth-owner") in [
             ["native-recovery"],
             ["native-two-factor"]
           ]

    path = response |> get_resp_header("location") |> hd() |> URI.parse() |> Map.fetch!(:path)
    assert path in ["/users/sign_in", "/settings/two_factor"]
    assert_native(fetch(RailsFormRequests.rails_session(response), path))
  end

  defp assert_native(response) do
    assert response.status in [200, 422]
    dom = LazyHTML.from_document(response.resp_body)
    assert Enum.count(LazyHTML.query(dom, "script[src='/native/auth_http.js']")) == 1

    legacy =
      Enum.any?(
        ~w(importmap data-controller data-turbo data-phx-main data-phx-session rails_bridge /native/app.js phx-hook),
        &String.contains?(response.resp_body, &1)
      )

    refute legacy

    for input <-
          LazyHTML.query(dom, "input:not([type=hidden]):not([type=submit]):not([type=button])") do
      id = List.first(LazyHTML.attribute(input, "id"))
      labelled = is_binary(id) and Enum.count(LazyHTML.query(dom, "label[for='#{id}']")) == 1
      assert labelled, "auth input needs exactly one accessible label"
    end

    refute Enum.any?(
             [:secret, :uri, :codes, :qr_svg, :render],
             &Map.has_key?(response.assigns, &1)
           )
  end

  test "every auth document and error response is Hotwire free with exactly one accessible label",
       c do
    for path <-
          ~w(/users/sign_in /users/sign_up /users/password/new /users/password/edit?reset_password_token=synthetic-reset /users/unlock/new),
        do: assert_native(fetch(c.guest, path))

    assert_native(
      submit(c.guest, "/users/sign_in", %{
        "user[email]" => c.actor.email,
        "user[password]" => "synthetic-wrong"
      })
    )

    assert_native(
      submit(c.guest, "/users", %{
        "user[email]" => "invalid",
        "user[password]" => "short",
        "user[password_confirmation]" => "other"
      })
    )

    for path <- ~w(/users/password /users/unlock),
        do: assert_native(submit(c.guest, path, %{"user[email]" => ""}))

    assert_native(
      submit(c.guest, "/users/password", %{
        "_method" => "put",
        "user[reset_password_token]" => "synthetic-invalid",
        "user[password]" => "short",
        "user[password_confirmation]" => "other"
      })
    )

    otp =
      submit(c.guest, "/users/sign_in", %{
        "user[email]" => c.otp.email,
        "user[password]" => "synthetic-password12"
      })

    assert_native(otp)

    assert_native(
      submit(RailsFormRequests.rails_session(otp), "/users/otp_challenge", %{
        "otp_attempt" => "synthetic-wrong"
      })
    )

    signed = RailsUser.session(c.actor.id)
    assert_native(fetch(signed, "/settings/two_factor"))
    setup = submit(signed, "/settings/two_factor")
    assert_native(setup)
    assert_native(submit(signed, "/settings/two_factor/verify", %{"otp_attempt" => "000000"}))

    {:ok, secret} =
      Dawarich.Auth.TwoFactor.Secret.decrypt(
        Repo.get!(Dawarich.Auth.Account, c.actor.id).otp_secret
      )

    backup =
      submit(signed, "/settings/two_factor/verify", %{
        "otp_attempt" =>
          Dawarich.Auth.TwoFactor.Totp.at(secret, DateTime.to_unix(DateTime.utc_now()))
      })

    assert_native(backup)
    assert_native(fetch(signed, "/settings/two_factor"))

    assert_native(
      submit(signed, "/settings/two_factor", %{
        "_method" => "delete",
        "password" => "synthetic-wrong",
        "otp_attempt" => "synthetic-wrong"
      })
    )

    pending =
      Map.put(c.guest, "pending_oauth_link", %{
        "user_id" => c.actor.id,
        "provider" => "github",
        "uid" => "synthetic-integration-uid",
        "expires_at" => DateTime.to_unix(DateTime.utc_now()) + 600
      })

    assert_native(fetch(pending, "/auth/account_link/challenge"))

    assert_native(
      submit(pending, "/auth/account_link/challenge", %{"password" => "synthetic-wrong"})
    )
  end

  test "native auth refusal never calls Rails and retained API/mobile responses stay unchanged",
       c do
    assert_native(fetch(c.guest, "/users/sign_in"))
    owner = self()
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:dawarich, :standalone, :handback],
        fn _, _, metadata, _ -> send(owner, {:native_refusal_reason, metadata.reason}) end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    upstream = Dawarich.Test.RawHTTP.listen()
    before = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    on_exit(fn ->
      :gen_tcp.close(upstream.listen)
      Application.put_env(:dawarich, :rails_upstream, before)
    end)

    for {path, expected} <- [
          {"/users/sign_in?locale=de", 422},
          {"/users/sign_up?unexpected=1", 400},
          {"/users/password/new?unexpected=1", 422},
          {"/users/unlock/new?unexpected=1", 422}
        ] do
      refused = get(build_conn(), path)
      assert refused.status == expected and refused.halted
      refute Map.has_key?(refused.resp_cookies, "_dawarich_session")
    end

    for headers <- [
          [{"origin", "https://foreign.invalid"}],
          [{"x-requested-with", "XMLHttpRequest"}],
          [{"accept", "text/vnd.turbo-stream.html"}]
        ] do
      refused =
        submit(
          c.guest,
          "/users/sign_in",
          %{"user[email]" => c.otp.email, "user[password]" => "synthetic-password12"},
          headers
        )

      assert refused.status == 422
      refute Map.has_key?(refused.resp_cookies, "_dawarich_session")
    end

    assert Repo.get!(Dawarich.Auth.Account, c.actor.id).failed_attempts == 0
    assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 0)

    refute_received {:native_refusal_reason, "rails_proxy"}

    api =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/v1/auth/login",
        Jason.encode!(%{email: "native-missing@example.test", password: "synthetic-wrong"})
      )

    assert api.status == 401
    assert get_resp_header(api, "x-dawarich-auth-owner") == ["native-api-auth"]
    assert Jason.decode!(api.resp_body)["error"] == "auth_failed"
    refute Map.has_key?(api.resp_cookies, "_dawarich_session")
    mobile = get(build_conn(), "/auth/ios/success")
    assert mobile.status == 200
    assert Jason.decode!(mobile.resp_body)["success"]
    refute Map.has_key?(mobile.resp_cookies, "_dawarich_session")
    refute String.contains?(mobile.resp_body, "auth_http")
  end
end
