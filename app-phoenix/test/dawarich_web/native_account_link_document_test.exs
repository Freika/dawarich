defmodule DawarichWeb.NativeAccountLinkDocumentTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf
  alias Dawarich.Auth.AccountLink.Closure
  @endpoint DawarichWeb.Endpoint
  @jwt "synthetic-link-jwt"
  @path "/auth/account_link/challenge"

  setup do
    Dawarich.Test.NativeAuthHTTP.isolate_counters()
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

    env = %{
      "DAWARICH_RAILS" => "off",
      "SELF_HOSTED" => "true",
      "FORCE_SSL" => "false",
      "JWT_SECRET_KEY" => @jwt
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
        email: "native-link-document@example.test",
        encrypted_password: Bcrypt.hash_pwd_salt("synthetic-password12", log_rounds: 4),
        api_key: "synthetic",
        settings: %{}
      })

    Dawarich.Test.NativeAuthHTTP.isolate_counters(actor.id)

    pending = %{
      "user_id" => actor.id,
      "provider" => "github",
      "uid" => "synthetic-link-uid",
      "provider_label" => "Provider <SSO>",
      "expires_at" => DateTime.to_unix(DateTime.utc_now()) + 600
    }

    %{
      actor: actor,
      session: %{"_csrf_token" => RailsCsrf.new_token(), "pending_oauth_link" => pending}
    }
  end

  defp fetch(session, path),
    do:
      build_conn() |> put_req_cookie("_dawarich_session", RailsUser.cookie(session)) |> get(path)

  defp page(c) do
    response = fetch(c.session, @path)
    assert response.status == 200
    assert response.resp_body =~ "/native/auth_http.js"
    response
  end

  defp submit(session, path, fields),
    do: Dawarich.Test.NativeAuthHTTP.post_form(session, URI.encode_query(fields), [], path)

  defp token(html, action),
    do:
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("form[action='#{action}'] input[name=authenticity_token]")
      |> LazyHTML.attribute("value")
      |> hd()

  defp link(c, value),
    do: fetch(c.session, "/auth/account_link?" <> URI.encode_query(%{"token" => value}))

  test "native account-link forms cannot exchange action tokens", c do
    html = page(c).resp_body
    assert html =~ "Provider &lt;SSO&gt;"
    first = token(html, @path)
    email = token(html, "/auth/account_link/email")
    distinct = first != email
    assert distinct

    for {path, wrong} <- [{@path, email}, {"/auth/account_link/email", first}] do
      rejected =
        submit(c.session, path, %{
          "authenticity_token" => wrong,
          "password" => "synthetic-password12"
        })

      assert rejected.status == 422
      assert is_nil(Repo.get!(Dawarich.Auth.Account, c.actor.id).provider)
      refute rejected.resp_cookies["_dawarich_session"]
    end
  end

  test "refused link password stays empty and alert lasts once", c do
    html = page(c).resp_body

    rejected =
      submit(c.session, @path, %{
        "authenticity_token" => token(html, @path),
        "password" => "synthetic-rejected-password"
      })

    assert rejected.status == 422
    refute rejected.resp_body =~ "synthetic-rejected-password"
    dom = LazyHTML.from_document(rejected.resp_body)
    assert Enum.count(LazyHTML.query(dom, "[data-auth-error-summary]")) == 1
    assert LazyHTML.attribute(LazyHTML.query(dom, "input[name=password]"), "value") in [[], [""]]
    state = RailsFormRequests.rails_session(rejected)
    assert state["pending_oauth_link_attempts"] == 1
    next = fetch(state, @path)

    assert Enum.empty?(
             LazyHTML.query(LazyHTML.from_document(next.resp_body), "[data-auth-error-summary]")
           )
  end

  test "emailed link binds target provider uid and cannot replay", c do
    assert page(c).status == 200
    {:ok, value} = Closure.issue(c.actor.id, "github", "synthetic-bound-uid", %{})
    [header, payload, _] = String.split(value, ".")

    invalid =
      payload
      |> Base.url_decode64!(padding: false)
      |> Jason.decode!()
      |> Map.put("purpose", "other")
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)

    input = header <> "." <> invalid

    wrong_purpose =
      input <> "." <> Base.url_encode64(:crypto.mac(:hmac, :sha256, @jwt, input), padding: false)

    refused = link(c, wrong_purpose)
    refute Map.has_key?(RailsFormRequests.rails_session(refused), "warden.user.user.key")
    assert is_nil(Repo.get!(Dawarich.Auth.Account, c.actor.id).provider)

    Repo.query!("UPDATE users SET provider='github',uid='different' WHERE id=$1", [c.actor.id],
      log: false
    )

    conflict = link(c, value)
    refute Map.has_key?(RailsFormRequests.rails_session(conflict), "warden.user.user.key")
    assert Repo.get!(Dawarich.Auth.Account, c.actor.id).uid == "different"
    Repo.query!("UPDATE users SET provider=NULL,uid=NULL WHERE id=$1", [c.actor.id], log: false)
    linked = link(c, value)
    assert linked.status == 302
    assert hd(hd(RailsFormRequests.rails_session(linked)["warden.user.user.key"])) == c.actor.id
    assert Repo.get!(Dawarich.Auth.Account, c.actor.id).uid == "synthetic-bound-uid"
    replay = link(c, value)
    refute Map.has_key?(RailsFormRequests.rails_session(replay), "warden.user.user.key")
  end

  test "MFA email linking redirects to sign-in without authenticating", c do
    assert page(c).status == 200

    Repo.query!("UPDATE users SET otp_required_for_login=true WHERE id=$1", [c.actor.id],
      log: false
    )

    {:ok, value} = Closure.issue(c.actor.id, "github", "synthetic-mfa-uid", %{})
    linked = link(c, value)
    assert linked.status == 302
    assert get_resp_header(linked, "location") == ["http://www.example.com/users/sign_in"]
    refute Map.has_key?(RailsFormRequests.rails_session(linked), "warden.user.user.key")
    assert Repo.get!(Dawarich.Auth.Account, c.actor.id).uid == "synthetic-mfa-uid"
  end

  test "native account-link email publishes durable intent without authenticating", c do
    html = page(c).resp_body
    Dawarich.Jobs.Ownership.put!(Repo, "command:mail.user.oauth_account_link", :oban)

    before =
      Repo.query!(
        "SELECT count(*) FROM job_outbox WHERE aggregate_id=$1 AND command_type='mail.user.oauth_account_link'",
        [c.actor.id], log: false).rows

    response =
      submit(c.session, "/auth/account_link/email", %{
        "authenticity_token" => token(html, "/auth/account_link/email")
      })

    assert response.status == 302

    after_count =
      Repo.query!(
        "SELECT count(*) FROM job_outbox WHERE aggregate_id=$1 AND command_type='mail.user.oauth_account_link'",
        [c.actor.id], log: false).rows

    assert after_count == [[hd(hd(before)) + 1]]

    [[payload]] =
      Repo.query!(
        "SELECT payload FROM job_outbox WHERE aggregate_id=$1 AND command_type='mail.user.oauth_account_link'",
        [c.actor.id], log: false).rows

    assert {:ok, args} = Dawarich.Mail.OauthAccountLinkWorker.args_from_command(1, payload)
    refute Map.has_key?(args, "link_url")
    refute Map.has_key?(RailsFormRequests.rails_session(response), "warden.user.user.key")
    assert is_nil(Repo.get!(Dawarich.Auth.Account, c.actor.id).provider)
  end
end
