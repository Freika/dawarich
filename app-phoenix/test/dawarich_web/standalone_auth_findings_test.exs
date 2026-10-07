defmodule DawarichWeb.StandaloneAuthFindingsTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Auth.{Account, Otp.Pending, TwoFactor.Secret, TwoFactor.Totp}
  alias Dawarich.Test.{RailsFormRequests, RailsUser}

  @endpoint DawarichWeb.Endpoint
  @path "/settings/two_factor"
  @otp_keys ~w(otp_user_id otp_challenge_at otp_failed_attempts otp_remember_me)

  setup do
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    Dawarich.State.put_registration_enabled(Repo, false)

    env = %{
      "DAWARICH_RAILS" => "off",
      "SELF_HOSTED" => "true",
      "FORCE_SSL" => "false",
      "JWT_SECRET_KEY" => "findings-synthetic-jwt-not-for-production",
      "OTP_ENCRYPTION_PRIMARY_KEY" => "findings-synthetic-primary",
      "OTP_ENCRYPTION_DETERMINISTIC_KEY" => "findings-synthetic-deterministic",
      "OTP_ENCRYPTION_KEY_DERIVATION_SALT" => "findings-synthetic-salt"
    }

    previous = Map.new(env, fn {name, _} -> {name, System.get_env(name)} end)
    System.put_env(env)

    on_exit(fn ->
      for {name, value} <- previous,
          do: if(value, do: System.put_env(name, value), else: System.delete_env(name))
    end)

    actors =
      for admin <- [false, true] do
        RailsUser.insert!(%{
          id: System.unique_integer([:positive]),
          email: "findings-#{admin}@example.test",
          encrypted_password: Bcrypt.hash_pwd_salt("findings-password", log_rounds: 4),
          api_key: "findings-#{admin}-synthetic",
          admin: admin,
          settings: %{"timezone" => "UTC", "locale" => "en", "onboarding_completed" => true}
        })
      end

    %{actors: actors}
  end

  @tag :f1_login
  test "F1 full login of actor B clears actor A's active OTP challenge", c do
    [actor_a, actor_b] = c.actors

    Repo.get!(Account, actor_a.id)
    |> Ecto.Changeset.change(otp_required_for_login: true)
    |> Repo.update!()

    pending = pending(actor_a) |> Map.put("locale", "de")
    fields = %{"user[email]" => actor_b.email, "user[password]" => "wrong"}
    denied = form(pending, "/users/sign_in", fields)
    assert denied.status == 422
    assert match?({:ok, _, _}, Pending.valid(RailsFormRequests.rails_session(denied), now()))

    login =
      form(pending, "/users/sign_in", Map.put(fields, "user[password]", "findings-password"))

    assert login.status == 303
    signed = RailsFormRequests.rails_session(login)
    refute Enum.any?(@otp_keys, &Map.has_key?(signed, &1))
    assert Pending.valid(signed, now()) == :expired
    assert signed["locale"] == "de"
    assert hd(hd(signed["warden.user.user.key"])) == actor_b.id

    for encode <- [
          &Dawarich.Auth.SessionCookie.for_account_link(&1, actor_b, :sign_in, "signed in", &2),
          &Dawarich.Auth.SessionCookie.for_restore(&1, actor_b, &2)
        ] do
      {state, _cookie} = encode.(pending, Dawarich.RailsSecret.fetch())
      refute Enum.any?(@otp_keys, &Map.has_key?(state, &1))
    end

    {linked, _cookie} =
      Dawarich.Auth.SessionCookie.for_account_link(
        pending,
        actor_b,
        :link_only,
        "linked",
        Dawarich.RailsSecret.fetch()
      )

    assert match?({:ok, _, _}, Pending.valid(linked, now()))

    for path <- [@path, "/settings/users", "/achievements"] do
      admitted = request(signed, :get, path)
      assert admitted.status == 200
      assert admitted.assigns.current_user.id == actor_b.id
    end

    System.put_env("DAWARICH_RAILS", "on")

    {coexisting, _cookie} =
      Dawarich.Auth.SessionCookie.for_login(
        pending,
        actor_b,
        "signed in",
        Dawarich.RailsSecret.fetch()
      )

    assert match?({:ok, _, _}, Pending.valid(coexisting, now()))
  end

  @tag :f1_guard
  test "F1 active pending challenge refuses Warden and remember credentials at shared pages", c do
    [actor_a, actor_b] = c.actors
    remember = remember(actor_b)
    pending = pending(actor_a)
    mixed = Map.merge(session(actor_b), pending)

    for {state, credential} <- [{mixed, nil}, {pending, remember}],
        method <- [:get, :head],
        path <- [@path, "/settings/users", "/settings/background_jobs", "/achievements"] do
      assert_sign_in(request(state, method, path, credential), path)
    end

    for {state, credential} <- [{mixed, nil}, {pending, remember}],
        path <- [@path, @path <> "/verify"] do
      assert_sign_in(form(state, path, %{}, credential), path)
    end

    for {state, credential} <- [{mixed, nil}, {pending, remember}] do
      expired = Map.put(state, "otp_challenge_at", now() - 301)
      assert request(expired, :get, "/achievements", credential).status == 200
    end

    assert Repo.get!(Account, actor_b.id).otp_secret == nil

    System.put_env("DAWARICH_RAILS", "on")

    coexisting =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(mixed))
      |> DawarichWeb.RailsAuth.call([])

    assert coexisting.assigns.current_user.id == actor_b.id
  end

  @tag :f2_remember
  test "F2 remember-only users manage OTP with salt lock CSRF and pending validation", c do
    for actor <- c.actors do
      remember = remember(actor)
      shown = request(nil, :get, @path, remember)
      assert shown.status == 200
      assert shown.assigns.current_user.id == actor.id
      state = RailsFormRequests.rails_session(shown)
      assert form(state, @path, %{"authenticity_token" => "invalid"}, remember).status == 422
      assert Repo.get!(Account, actor.id).otp_secret == nil
      setup = form(state, @path, %{}, remember)
      assert setup.status == 200
      state = RailsFormRequests.rails_session(setup)
      account = Repo.get!(Account, actor.id)
      {:ok, secret} = Secret.decrypt(account.otp_secret)

      verify =
        form(state, @path <> "/verify", %{"otp_attempt" => Totp.at(secret, now())}, remember)

      assert verify.status == 200
      assert Repo.get!(Account, actor.id).otp_required_for_login

      codes =
        verify.resp_body
        |> LazyHTML.from_document()
        |> LazyHTML.query("code")
        |> LazyHTML.to_tree()

      assert length(codes) == 10
      {_, _, code} = hd(codes)
      state = RailsFormRequests.rails_session(verify)

      disabled =
        form(
          state,
          @path,
          %{
            "_method" => "delete",
            "password" => "findings-password",
            "otp_attempt" => IO.iodata_to_binary(code)
          },
          remember
        )

      assert disabled.status == 302
      refute Repo.get!(Account, actor.id).otp_required_for_login
      assert Repo.get!(Account, actor.id).otp_secret == nil

      Repo.get!(Account, actor.id)
      |> Ecto.Changeset.change(locked_at: DateTime.utc_now())
      |> Repo.update!()

      locked = request(%{}, :get, @path, remember)
      assert locked.status == 302
      refute locked.assigns.current_user

      Repo.get!(Account, actor.id)
      |> Ecto.Changeset.change(
        locked_at: nil,
        encrypted_password: Bcrypt.hash_pwd_salt("changed", log_rounds: 4)
      )
      |> Repo.update!()

      assert_sign_in(request(%{}, :get, @path, remember), @path)
    end
  end

  @tag :f3_head
  test "F3 authenticated HEAD uses GET admission and an empty response body", c do
    for actor <- c.actors,
        credential <- [nil, remember(actor)],
        path <- [@path, "/settings/background_jobs", "/achievements"] do
      state = if credential, do: %{}, else: session(actor)
      get = request(state, :get, path, credential)
      head = request(state, :head, path, credential)
      assert get.status == 200
      assert head.status == get.status
      assert head.resp_body == ""
      assert get_resp_header(head, "content-type") == get_resp_header(get, "content-type")

      assert get_resp_header(head, "x-dawarich-auth-owner") ==
               get_resp_header(get, "x-dawarich-auth-owner")
    end

    for state <- [%{}, pending(hd(c.actors))],
        do: assert_sign_in(request(state, :head, @path), @path)
  end

  @tag :f4_query
  test "F4 locale reads authenticate and render while query writes stay strict", c do
    path = @path <> "?locale=de"

    for state <- [%{}, pending(hd(c.actors))], method <- [:get, :head] do
      conn = request(state, method, path)
      assert conn.status == 302
      assert conn.resp_body == ""
      assert get_resp_header(conn, "location") == ["http://www.example.com/users/sign_in"]
      assert RailsFormRequests.rails_session(conn)["user_return_to"] == path
      refute conn.assigns.current_user
    end

    for actor <- c.actors, credential <- [nil, remember(actor)] do
      state = if credential, do: %{}, else: session(actor)
      conn = request(state, :get, path, credential)
      assert conn.status == 200
      assert conn.assigns.locale == "de"
      assert request(state, :head, path, credential).status == 200
      state = RailsFormRequests.rails_session(conn)
      assert form(state, path, %{}, credential).status == 422
      assert Repo.get!(Account, actor.id).otp_secret == nil
    end
  end

  defp session(actor),
    do:
      RailsUser.session(actor.id, %{
        "warden.user.user.key" => [[actor.id], binary_part(actor.encrypted_password, 0, 29)]
      })

  defp now, do: DateTime.to_unix(DateTime.utc_now())

  defp pending(actor),
    do: %{
      "otp_user_id" => actor.id,
      "otp_challenge_at" => now(),
      "otp_failed_attempts" => 1,
      "otp_remember_me" => true,
      "_csrf_token" => DawarichWeb.RailsCsrf.new_token()
    }

  defp remember(actor) do
    at = DateTime.add(DateTime.utc_now(), -60)

    Repo.get!(Account, actor.id)
    |> Ecto.Changeset.change(remember_created_at: at)
    |> Repo.update!()

    payload = [
      [actor.id],
      binary_part(actor.encrypted_password, 0, 29),
      Dawarich.Accounts.remember_generated_at(DateTime.add(at, 1))
    ]

    Dawarich.RailsCookies.sign(
      payload,
      "remember_user_token",
      Dawarich.RailsSecret.fetch(),
      DateTime.add(DateTime.utc_now(), 3600)
    )
  end

  defp request(state, method, path, remember \\ nil, body \\ nil) do
    cookies = if state, do: ["_dawarich_session=" <> RailsUser.cookie(state)], else: []
    cookies = if remember, do: cookies ++ ["remember_user_token=" <> remember], else: cookies

    conn =
      build_conn()
      |> put_req_header("cookie", Enum.join(cookies, "; "))
      |> put_req_header("accept", "text/html")

    conn =
      if body do
        conn
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> put_req_header("content-length", to_string(byte_size(body)))
      else
        conn
      end

    dispatch(conn, @endpoint, method, path, body)
  end

  defp form(state, path, fields, remember \\ nil) do
    body =
      fields
      |> Map.put_new("authenticity_token", DawarichWeb.RailsCsrf.masked_token(state))
      |> URI.encode_query()

    request(state, :post, path, remember, body)
  end

  defp assert_sign_in(conn, path) do
    assert conn.status == 302
    assert conn.resp_body == ""
    assert get_resp_header(conn, "location") == ["http://www.example.com/users/sign_in"]
    assert RailsFormRequests.rails_session(conn)["user_return_to"] == path
    refute conn.assigns.current_user
  end
end
