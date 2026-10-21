defmodule DawarichWeb.NativeRecoveryDocumentTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf
  alias Dawarich.Auth.Recovery.Token
  @endpoint DawarichWeb.Endpoint

  setup do
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    env = %{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true", "FORCE_SSL" => "false"}
    old = Map.new(env, fn {k, _} -> {k, System.get_env(k)} end)
    System.put_env(env)
    config = Application.fetch_env(:dawarich, :recovery_context)
    Application.put_env(:dawarich, :recovery_context, %{enqueue: fn _ -> :ok end, log_rounds: 4})

    on_exit(fn ->
      for {k, v} <- old, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))

      case config do
        {:ok, value} -> Application.put_env(:dawarich, :recovery_context, value)
        :error -> Application.delete_env(:dawarich, :recovery_context)
      end
    end)

    Dawarich.State.put_registration_enabled(Repo, true)

    actor =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "native-recovery@example.test",
        encrypted_password: Bcrypt.hash_pwd_salt("synthetic-password12", log_rounds: 4),
        api_key: "synthetic",
        settings: %{}
      })

    %{actor: actor, guest: %{"_csrf_token" => RailsCsrf.new_token()}}
  end

  defp page(c, path) do
    response =
      build_conn() |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.guest)) |> get(path)

    assert response.resp_body =~ "/native/auth_http.js"
    response
  end

  defp submit(c, path, fields, method \\ "POST") do
    RailsFormRequests.post_form(
      c.guest,
      URI.encode_query(
        Map.put(fields, "authenticity_token", RailsCsrf.masked_form_token(c.guest, path, method))
      ),
      [],
      path
    )
  end

  defp public(response) do
    {response.status, Plug.Conn.get_resp_header(response, "location"),
     RailsFormRequests.rails_session(response)["flash"]}
  end

  test "native recovery known unknown and unlocked requests have identical public notice", c do
    assert page(c, "/users/password/new").status == 200

    for path <- ["/users/password", "/users/unlock"] do
      known = submit(c, path, %{"user[email]" => c.actor.email})
      unknown = submit(c, path, %{"user[email]" => "unknown@example.test"})
      assert public(known) == public(unknown)
      assert known.status == 303
    end
  end

  test "failed recovery enqueue restores digest and job state", c do
    assert page(c, "/users/password/new").status == 200
    before = Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows

    Application.put_env(:dawarich, :recovery_context, %{
      enqueue: fn notification ->
        sealed =
          Dawarich.RailsCookies.encrypt(
            notification.raw,
            "synthetic-recovery-intent",
            Dawarich.RailsSecret.fetch()
          )

        Repo.query!(
          "INSERT INTO job_outbox(event_id,command_type,command_version,payload,aggregate_id,scheduled_at,metadata) VALUES(gen_random_uuid(),'mail.recovery',1,$1,$2,now(),'{}')",
          [%{"sealed" => sealed}, c.actor.id],
          log: false
        )

        {:error, :synthetic_enqueue_failure}
      end
    })

    failed = submit(c, "/users/password", %{"user[email]" => c.actor.email})
    assert failed.status == 500
    assert is_nil(Repo.get!(Dawarich.Auth.Account, c.actor.id).reset_password_token)
    assert Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows == before
  end

  test "native reset retires the old session and permits one token redemption", c do
    raw = "synthetic-reset-capability"
    digest = Token.digest(:reset_password_token, raw, Dawarich.RailsSecret.fetch())

    Repo.query!(
      "UPDATE users SET reset_password_token=$2,reset_password_sent_at=now(),remember_created_at=now()-interval '1 minute' WHERE id=$1",
      [c.actor.id, digest],
      log: false
    )

    old_session = %{
      "warden.user.user.key" => [[c.actor.id], String.slice(c.actor.encrypted_password, 0, 29)]
    }

    remember = [
      [c.actor.id],
      String.slice(c.actor.encrypted_password, 0, 29),
      Dawarich.Accounts.remember_generated_at(DateTime.utc_now())
    ]

    assert Dawarich.Accounts.from_session(old_session, DateTime.utc_now())

    assert Dawarich.Accounts.remembered?(
             Dawarich.Accounts.get(c.actor.id),
             remember,
             DateTime.utc_now()
           )

    assert page(c, "/users/password/edit?reset_password_token=" <> raw).status == 200

    params = %{
      "_method" => "put",
      "user[reset_password_token]" => raw,
      "user[password]" => "synthetic-new-password12",
      "user[password_confirmation]" => "synthetic-new-password12"
    }

    reset = submit(c, "/users/password", params, "PUT")
    assert reset.status == 303
    refute Dawarich.Accounts.from_session(old_session, DateTime.utc_now())

    refute Dawarich.Accounts.remembered?(
             Dawarich.Accounts.get(c.actor.id),
             remember,
             DateTime.utc_now()
           )

    replay = submit(c, "/users/password", params, "PUT")
    assert replay.status == 422
    assert replay.resp_body =~ "/native/auth_http.js"
    refute Map.has_key?(RailsFormRequests.rails_session(replay), "warden.user.user.key")
  end

  test "unlock redemption never authenticates and replay returns request errors", c do
    raw = "synthetic-unlock-capability"

    Repo.query!(
      "UPDATE users SET unlock_token=$2,locked_at=now() WHERE id=$1",
      [c.actor.id, Token.digest(:unlock_token, raw, Dawarich.RailsSecret.fetch())],
      log: false
    )

    assert page(c, "/users/unlock/new").status == 200
    target = "/users/unlock?unlock_token=" <> raw

    response =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.guest))
      |> get(target)

    assert response.status == 302
    refute Map.has_key?(RailsFormRequests.rails_session(response), "warden.user.user.key")

    replay =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.guest))
      |> get(target)

    assert replay.status == 200
    assert replay.resp_body =~ "/native/auth_http.js"

    assert Enum.count(
             LazyHTML.query(LazyHTML.from_document(replay.resp_body), "[data-auth-error-summary]")
           ) == 1

    refute Map.has_key?(RailsFormRequests.rails_session(replay), "warden.user.user.key")
  end
end
