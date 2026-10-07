defmodule DawarichWeb.StandaloneAccountDeletionTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.{Repo, Redis}
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
    for spec <- Redis.cache_child_specs(), do: start_supervised!(spec)
    previous = Map.new(~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL), &{&1, System.get_env(&1)})
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    System.put_env("FORCE_SSL", "false")
    actor = user("actor")
    other = user("other")
    session = RailsUser.session(actor.id)

    on_exit(fn ->
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
      ids = [actor.id, other.id]
      rows("DELETE FROM job_outbox WHERE aggregate_id=ANY($1::bigint[])", [ids])
      rows("DELETE FROM family_memberships WHERE user_id=ANY($1::bigint[])", [ids])
      rows("DELETE FROM families WHERE creator_id=ANY($1::bigint[])", [ids])
      rows("DELETE FROM users WHERE id=ANY($1::bigint[])", [ids])
      for id <- ids, do: Redis.cache_command(["DEL", "account_destroy:rate_limit:#{id}"])

      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    %{actor: actor, other: other, session: session}
  end

  @tag :sa_destroy_csrf_sources
  test "browser accepts valid form and header CSRF together as Rails does", c do
    token = RailsCsrf.masked_form_token(c.session, "/users", "delete")

    for {form_token, header_token} <- [{token, token}, {"invalid", token}, {token, "invalid"}] do
      raw =
        URI.encode_query(%{
          "_method" => "delete",
          "confirm_email" => c.actor.email,
          "authenticity_token" => form_token
        })

      conn =
        RailsFormRequests.post_form(
          c.session,
          raw,
          [{"accept", "text/html"}, {"x-csrf-token", header_token}],
          "/users"
        )

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://www.example.com/"]
      assert count(c.actor.id) == 1
      assert live?(c.other.id)
      rows("UPDATE users SET deleted_at=NULL WHERE id=$1", [c.actor.id])
      rows("DELETE FROM job_outbox WHERE aggregate_id=$1", [c.actor.id])
    end

    invalid =
      RailsFormRequests.post_form(
        c.session,
        URI.encode_query(%{
          "_method" => "delete",
          "confirm_email" => c.actor.email,
          "authenticity_token" => "invalid"
        }),
        [{"accept", "text/html"}, {"x-csrf-token", "invalid"}],
        "/users"
      )

    assert invalid.status == 422
    assert count(c.actor.id) == 0
  end

  @tag :sa_destroy_irrelevant_id
  test "browser ignores irrelevant target id as Rails does", c do
    conn = form(c, %{"confirm_email" => c.actor.email, "id" => to_string(c.other.id)})
    assert conn.status == 302
    assert get_resp_header(conn, "location") == ["http://www.example.com/"]
    assert count(c.actor.id) == 1
    refute live?(c.actor.id)
    assert live?(c.other.id)
    assert count(c.other.id) == 0
  end

  @tag :sa_destroy_browser
  test "standalone browser deletion authenticates owner and CSRF then schedules once", c do
    invalid = form(c, %{"confirm_email" => c.actor.email, "authenticity_token" => "invalid"})
    assert invalid.status == 422
    assert count(c.actor.id) == 0
    wrong = form(c, %{"confirm_email" => c.other.email})
    assert wrong.status == 302
    assert flash(wrong) == %{"alert" => "Type your email address to confirm deletion."}
    assert live?(c.actor.id)
    saved = form(c, %{"confirm_email" => c.actor.email})
    assert saved.status == 302
    assert get_resp_header(saved, "location") == ["http://www.example.com/"]
    assert flash(saved) == %{"notice" => "Your account has been scheduled for deletion."}
    refute Map.has_key?(RailsFormRequests.rails_session(saved), "warden.user.user.key")
    assert saved.resp_cookies["remember_user_token"].max_age == 0
    refute live?(c.actor.id)
    assert live?(c.other.id)
    assert count(c.actor.id) == 1
    repeated = form(c, %{"confirm_email" => c.actor.email})
    assert repeated.status == 302
    assert get_resp_header(repeated, "location") == ["http://www.example.com/users/sign_in"]
    assert count(c.actor.id) == 1
    hash = Bcrypt.hash_pwd_salt("synthetic-password", log_rounds: 4)
    rows("UPDATE users SET provider=NULL, encrypted_password=$2 WHERE id=$1", [c.other.id, hash])

    session =
      RailsUser.session(c.other.id)
      |> Map.put("warden.user.user.key", [[c.other.id], String.slice(hash, 0, 29)])

    raw =
      URI.encode_query(%{
        "password" => "synthetic-password",
        "authenticity_token" => RailsCsrf.masked_form_token(session, "/users", "delete")
      })

    direct =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", to_string(byte_size(raw)))
      |> dispatch(@endpoint, :delete, "/users", raw)

    assert direct.status == 302
    assert count(c.other.id) == 1
    refute live?(c.other.id)
  end

  @tag :sa_destroy_api
  test "standalone API deletion uses API owner and permits pending payment with Rails errors",
       c do
    assert api(nil, %{}).status == 401
    wrong = api(c.actor, %{"confirm_email" => c.other.email, "user_id" => c.other.id})
    assert wrong.status == 401

    assert Jason.decode!(wrong.resp_body) == %{
             "error" => "password_required",
             "message" => "Type your email address to confirm deletion."
           }

    rows("UPDATE users SET status=3 WHERE id=$1", [c.actor.id])

    saved =
      api(c.actor, %{"confirm_email" => String.upcase(c.actor.email), "user_id" => c.other.id})

    assert saved.status == 200

    assert Jason.decode!(saved.resp_body) == %{
             "message" => "Your account has been scheduled for deletion."
           }

    assert count(c.actor.id) == 1
    assert live?(c.other.id)
    assert api(c.actor, %{"confirm_email" => c.actor.email}).status == 401
    assert count(c.actor.id) == 1

    rows("UPDATE users SET provider=NULL, encrypted_password=$2 WHERE id=$1", [
      c.other.id,
      Bcrypt.hash_pwd_salt("synthetic-password", log_rounds: 4)
    ])

    refused = api(c.other, %{"password" => "wrong"})
    assert refused.status == 401

    assert Jason.decode!(refused.resp_body)["message"] ==
             "Provide your current password to delete your account."

    assert api(c.other, %{"password" => "synthetic-password"}).status == 200
    assert count(c.other.id) == 1
  end

  @tag :sa_destroy_confirmation
  test "standalone Cloud request mails once and confirmation preserves another user's session",
       c do
    System.put_env("SELF_HOSTED", "false")
    sent = api(c.actor, %{})
    assert sent.status == 202

    assert Jason.decode!(sent.resp_body)["message"] ==
             "A confirmation email has been sent. Click the link in the email to permanently delete your account."

    assert live?(c.actor.id)
    assert api(c.actor, %{}).status == 429

    assert [[payload]] =
             rows(
               "SELECT payload FROM job_outbox WHERE aggregate_id=$1 AND command_type='mail.user.account_destroy_confirmation'",
               [c.actor.id]
             )

    url = URI.parse(payload["link_url"])
    confirm = browser_get(RailsUser.session(c.other.id), url.path <> "?" <> url.query)
    assert confirm.status == 302
    assert get_resp_header(confirm, "cache-control") == ["no-store"]
    assert get_resp_header(confirm, "pragma") == ["no-cache"]
    session = RailsFormRequests.rails_session(confirm)

    assert session["warden.user.user.key"] ==
             RailsUser.session(c.other.id)["warden.user.user.key"]

    assert flash(confirm) == %{
             "notice" =>
               "Your account has been scheduled for deletion. We are sorry to see you go."
           }

    assert count(c.actor.id) == 1
    replay = browser_get(session, url.path <> "?" <> url.query)
    assert flash(replay) == %{"alert" => "This deletion link has already been used."}
    invalid = browser_get(session, "/users/me/destroy/confirm?token=invalid")
    assert flash(invalid) == %{"alert" => "Deletion link invalid or expired."}
    assert count(c.actor.id) == 1
    assert live?(c.other.id)
  end

  @tag :sa_destroy_rollback
  test "standalone deletion rolls back a failed enqueue and retries exactly once", c do
    rows(
      "ALTER TABLE job_outbox ADD CONSTRAINT sa_destroy_failure CHECK(command_type <> 'users.destroy') NOT VALID"
    )

    try do
      assert api(c.actor, %{"confirm_email" => c.actor.email}).status == 503
      assert live?(c.actor.id)
      assert count(c.actor.id) == 0
    after
      rows("ALTER TABLE job_outbox DROP CONSTRAINT sa_destroy_failure")
    end

    assert api(c.actor, %{"confirm_email" => c.actor.email}).status == 200
    assert api(c.actor, %{"confirm_email" => c.actor.email}).status == 401
    assert count(c.actor.id) == 1
  end

  @tag :sa_destroy_mail_contract
  test "standalone deletion mail uses the configured Rails mail domain for API and browser", c do
    System.put_env("SELF_HOSTED", "false")
    saved = System.get_env("DOMAIN")
    System.put_env("DOMAIN", "mail.synthetic.invalid")

    on_exit(fn ->
      if saved, do: System.put_env("DOMAIN", saved), else: System.delete_env("DOMAIN")
    end)

    assert api(c.actor, %{}).status == 202
    other = %{c | actor: c.other, session: RailsUser.session(c.other.id)}
    sent = form(other, %{})
    assert sent.status == 302

    assert flash(sent)["notice"] ==
             "A confirmation email has been sent. Click the link in the email to permanently delete your account."

    for id <- [c.actor.id, c.other.id] do
      [[payload]] =
        rows(
          "SELECT payload FROM job_outbox WHERE aggregate_id=$1 AND command_type='mail.user.account_destroy_confirmation'",
          [id]
        )

      url = URI.parse(payload["link_url"])
      assert url.host == "mail.synthetic.invalid"
      assert url.scheme == "https"
      assert url.path == "/users/me/destroy/confirm"
      assert live?(id)
    end
  end

  @tag :sa_destroy_mail_retry
  test "standalone confirmation mail failure releases its rate slot for one retry", c do
    System.put_env("SELF_HOSTED", "false")

    rows(
      "ALTER TABLE job_outbox ADD CONSTRAINT sa_mail_failure CHECK(command_type <> 'mail.user.account_destroy_confirmation') NOT VALID"
    )

    try do
      assert api(c.actor, %{}).status == 503
      assert live?(c.actor.id)
      assert rows("SELECT 1 FROM job_outbox WHERE aggregate_id=$1", [c.actor.id]) == []
    after
      rows("ALTER TABLE job_outbox DROP CONSTRAINT sa_mail_failure")
    end

    assert api(c.actor, %{}).status == 202
    assert api(c.actor, %{}).status == 429
    assert rows("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [c.actor.id]) == [[1]]
  end

  @tag :sa_destroy_family
  test "standalone deletion refuses family owners before password or mail effects", c do
    [[family]] =
      rows(
        "INSERT INTO families(creator_id,name,created_at,updated_at) VALUES($1,'Synthetic',now(),now()) RETURNING id",
        [c.actor.id]
      )

    for {user, role} <- [{c.actor.id, 0}, {c.other.id, 1}],
        do:
          rows(
            "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,$3,now(),now())",
            [family, user, role]
          )

    refused = api(c.actor, %{})
    assert refused.status == 422
    assert Jason.decode!(refused.resp_body)["error"] == "cannot_delete_account"
    assert form(c, %{}).status == 302
    assert flash(form(c, %{}))["alert"] =~ "family"
    System.put_env("SELF_HOSTED", "false")
    assert api(c.actor, %{}).status == 422
    assert live?(c.actor.id)
    assert count(c.actor.id) == 0
    assert rows("SELECT 1 FROM job_outbox WHERE aggregate_id=$1", [c.actor.id]) == []
  end

  defp user(label) do
    RailsUser.insert!(%{
      id: :binary.decode_unsigned(:crypto.strong_rand_bytes(6)) + 1,
      email: "#{label}-#{Ecto.UUID.generate()}@example.invalid",
      api_key: "synthetic-#{Ecto.UUID.generate()}",
      provider: "openid_connect"
    })
  end

  defp form(c, params) do
    params =
      Map.merge(
        %{
          "_method" => "delete",
          "authenticity_token" => RailsCsrf.masked_form_token(c.session, "/users", "delete")
        },
        params
      )

    RailsFormRequests.post_form(
      c.session,
      URI.encode_query(params),
      [{"accept", "text/html"}],
      "/users"
    )
  end

  defp api(user, params) do
    body = Jason.encode!(params)

    conn =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-length", to_string(byte_size(body)))

    conn =
      if user, do: put_req_header(conn, "authorization", "Bearer " <> user.api_key), else: conn

    dispatch(conn, @endpoint, :delete, "/api/v1/users/me", body)
  end

  defp browser_get(session, path),
    do:
      build_conn() |> put_req_cookie("_dawarich_session", RailsUser.cookie(session)) |> get(path)

  defp flash(conn), do: RailsFormRequests.rails_session(conn)["flash"]["flashes"]

  defp count(id),
    do:
      rows(
        "SELECT count(*) FROM job_outbox WHERE aggregate_id=$1 AND command_type='users.destroy'",
        [id]
      )
      |> hd()
      |> hd()

  defp live?(id), do: rows("SELECT deleted_at IS NULL FROM users WHERE id=$1", [id]) == [[true]]
  defp rows(sql, params \\ []), do: Repo.query!(sql, params, log: false).rows
end
