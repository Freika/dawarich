defmodule DawarichWeb.NativeCredentialsDocumentTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.{AuthForm, RailsCsrf}
  @endpoint DawarichWeb.Endpoint

  setup do
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    env = %{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true", "FORCE_SSL" => "false"}
    old = Map.new(env, fn {k, _} -> {k, System.get_env(k)} end)
    System.put_env(env)

    on_exit(fn ->
      for {k, v} <- old, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
    end)

    Dawarich.State.put_registration_enabled(Repo, true)
    :ok
  end

  test "native sign-in fields preserve Devise submission and clear rejected password" do
    session = %{"_csrf_token" => RailsCsrf.new_token()}
    token = RailsCsrf.masked_form_token(session, "/users/sign_in", "POST")

    response =
      RailsFormRequests.post_form(
        session,
        URI.encode_query(%{
          "authenticity_token" => token,
          "user[email]" => "missing@example.test",
          "user[password]" => "synthetic-rejected-password",
          "user[remember_me]" => "1",
          "commit" => "Log in"
        }),
        [],
        "/users/sign_in"
      )

    assert response.status == 422
    dom = LazyHTML.from_document(response.resp_body)
    assert Enum.count(LazyHTML.query(dom, "form[data-auth-form][action='/users/sign_in']")) == 1

    assert LazyHTML.attribute(LazyHTML.query(dom, "input[name='user[remember_me]']"), "value") ==
             ["0", "1"]

    assert LazyHTML.attribute(LazyHTML.query(dom, "input[name='user[password]']"), "value") in [
             [],
             [""]
           ]

    refute response.resp_body =~ "synthetic-rejected-password"
    assert response.resp_body =~ "/native/auth_http.js"
    assert get_resp_header(response, "x-dawarich-auth-owner") == []
  end

  test "sign-in exposes only available provider entries and honors email-password policy" do
    conn = build_conn() |> assign(:rails_session, %{"_csrf_token" => RailsCsrf.new_token()})

    env = %{
      "SELF_HOSTED" => "true",
      "OIDC_CLIENT_ID" => "synthetic",
      "OIDC_PKCE_ENABLED" => "true",
      "ALLOW_EMAIL_PASSWORD_LOGIN" => "false",
      "OIDC_PROVIDER_NAME" => "Organization <SSO>"
    }

    public = apply(DawarichWeb.AuthProviderEntries, :for_request, [conn, env])
    html = AuthForm.render("synthetic-csrf", "", Map.to_list(public))
    dom = LazyHTML.from_fragment(html)
    assert LazyHTML.query(dom, "input[name='user[password]']") |> Enum.empty?()

    assert LazyHTML.attribute(LazyHTML.query(dom, "form"), "action") == [
             "/users/auth/openid_connect"
           ]

    assert html =~ "Organization &lt;SSO&gt;"
    refute html =~ "client_secret"

    cloud =
      apply(DawarichWeb.AuthProviderEntries, :for_request, [
        put_req_header(conn, "user-agent", "Android"),
        %{
          "SELF_HOSTED" => "false",
          "GOOGLE_OAUTH_CLIENT_ID" => "synthetic",
          "GOOGLE_OAUTH_CLIENT_SECRET" => "synthetic"
        }
      ])

    assert cloud.email_password
    assert cloud.providers == []
  end

  test "logout retires both devices and stale salt cannot restore" do
    actor =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "native-logout@example.test",
        api_key: "synthetic",
        settings: %{}
      })

    session = RailsUser.session(actor.id)
    old = Dawarich.Accounts.get(actor.id)
    stamp = Dawarich.Accounts.remember_generated_at(DateTime.utc_now())
    remember = [[actor.id], String.slice(old.encrypted_password, 0, 29), stamp]

    Repo.query!(
      "UPDATE users SET remember_created_at=$2 WHERE id=$1",
      [actor.id, DateTime.add(DateTime.utc_now(), -60)],
      log: false
    )

    assert Dawarich.Accounts.remembered?(
             Dawarich.Accounts.get(actor.id),
             remember,
             DateTime.utc_now()
           )

    page =
      build_conn()
      |> put_req_cookie(
        "_dawarich_session",
        RailsUser.cookie(%{"_csrf_token" => RailsCsrf.new_token()})
      )
      |> get("/users/sign_in")

    assert page.resp_body =~ "/native/auth_http.js"

    response =
      RailsFormRequests.post_form(
        session,
        URI.encode_query(%{
          "_method" => "delete",
          "authenticity_token" =>
            RailsCsrf.masked_form_token(session, "/users/sign_out", "DELETE")
        }),
        [],
        "/users/sign_out"
      )

    assert response.status == 303
    current = Dawarich.Accounts.get(actor.id)
    refute Dawarich.Accounts.remembered?(current, remember, DateTime.utc_now())

    assert Dawarich.Auth.Credentials.restore(remember, %{native: true, self_hosted: true}) ==
             {:error, :invalid}

    changed = Bcrypt.hash_pwd_salt("synthetic-changed-password", log_rounds: 4)

    Repo.query!("UPDATE users SET encrypted_password=$2 WHERE id=$1", [actor.id, changed],
      log: false
    )

    assert is_nil(Dawarich.Accounts.from_session(session, DateTime.utc_now()))
  end
end
