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
