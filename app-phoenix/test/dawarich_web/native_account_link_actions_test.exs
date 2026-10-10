defmodule DawarichWeb.NativeAccountLinkActionsTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf

  setup do
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

    env = %{
      "DAWARICH_RAILS" => "off",
      "SELF_HOSTED" => "true",
      "FORCE_SSL" => "false",
      "JWT_SECRET_KEY" => "synthetic-link-jwt"
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
        email: "native-link-actions@example.test",
        encrypted_password: Bcrypt.hash_pwd_salt("synthetic-password12", log_rounds: 4),
        api_key: "synthetic",
        settings: %{}
      })

    pending = %{
      "user_id" => actor.id,
      "provider" => "github",
      "uid" => "synthetic-link-uid",
      "provider_label" => "GitHub",
      "expires_at" => DateTime.to_unix(DateTime.utc_now()) + 600
    }

    %{
      actor: actor,
      session: %{"_csrf_token" => RailsCsrf.new_token(), "pending_oauth_link" => pending},
      context: %{repo: Repo, env: env}
    }
  end

  defp request(c, password) do
    path = "/auth/account_link/challenge"

    body =
      URI.encode_query(%{
        "password" => password,
        "authenticity_token" => RailsCsrf.masked_form_token(c.session, path, "POST")
      })

    conn =
      Phoenix.ConnTest.build_conn(:post, path, body)
      |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(c.session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(body)))

    apply(DawarichWeb.AuthAccountLink.Actions, :call, [conn, [enabled: true, context: c.context]])
  end

  test "account-link actions preserve wrong-password attempt cookie and source 422", c do
    failed = request(c, "synthetic-wrong-password")
    assert failed.status == 422
    updated = RailsFormRequests.rails_session(failed)
    assert updated["pending_oauth_link_attempts"] == 1
    assert updated["pending_oauth_link"]["user_id"] == c.actor.id
    assert get_resp_header(failed, "cache-control") == ["no-store"]
    assert get_resp_header(failed, "pragma") == ["no-cache"]
    refute Map.has_key?(updated, "warden.user.user.key")
    refute failed.resp_body =~ "synthetic-wrong-password"
  end

  test "MFA linking never creates Warden identity", c do
    Repo.query!("UPDATE users SET otp_required_for_login=true WHERE id=$1", [c.actor.id],
      log: false
    )

    linked = request(c, "synthetic-password12")
    assert linked.status == 302
    assert get_resp_header(linked, "location") == ["http://www.example.com/users/sign_in"]
    state = RailsFormRequests.rails_session(linked)
    refute Map.has_key?(state, "warden.user.user.key")
    refute Map.has_key?(state, "pending_oauth_link")
    assert Repo.get!(Dawarich.Auth.Account, c.actor.id).provider == "github"
  end

  test "account-link domain has no conn response dispatch and issuer callers still work", c do
    source = File.read!("lib/dawarich/auth/account_link/closure.ex")
    refute source =~ "import Plug.Conn"
    refute source =~ "DawarichWeb"
    assert Code.ensure_loaded?(Dawarich.Auth.AccountLink.Closure)
    refute function_exported?(Dawarich.Auth.AccountLink.Closure, :route, 3)

    {:ok, token} =
      Dawarich.Auth.AccountLink.Closure.issue(
        c.actor.id,
        "github",
        "synthetic-issued-uid",
        c.context
      )

    assert is_binary(token)

    assert {:ok, %{kind: :sign_in}} =
             Dawarich.Auth.AccountLink.Closure.confirm(
               token,
               %{},
               Map.put(c.context, :ip, "127.0.0.1")
             )
  end
end
