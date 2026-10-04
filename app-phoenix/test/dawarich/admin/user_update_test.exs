defmodule Dawarich.Admin.UserUpdateTest do
  use ExUnit.Case, async: false
  alias Dawarich.Admin.UserUpdate
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  @now ~U[2026-10-04 10:00:00.000000Z]
  @password "a10b-old-password"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    hash = Bcrypt.hash_pwd_salt(@password, log_rounds: 4)

    for {id, admin} <- [{15201, true}, {15202, false}] do
      RailsUser.insert!(%{
        id: id,
        email: "a10b-update-#{id}@example.invalid",
        admin: admin,
        encrypted_password: hash,
        settings: %{"locale" => "en", "timezone" => "UTC"},
        updated_at: ~N[2026-10-03 10:00:00],
        reset_password_token: "synthetic-reset-#{id}",
        reset_password_sent_at: ~N[2026-10-03 10:00:00],
        unlock_token: "synthetic-unlock-#{id}",
        failed_attempts: 3,
        failed_otp_attempts: 2,
        otp_locked_at: ~N[2026-10-03 10:00:00],
        remember_created_at: ~N[2026-10-03 10:00:00]
      })
    end

    %{
      actor: Accounts.get(15201),
      context: %{self_hosted: true, oidc: false, locale: "en", clock: fn -> @now end},
      hash: hash
    }
  end

  test "updates target credentials without current password", c do
    assert Code.ensure_loaded?(UserUpdate), "admin update must exist"
    before = snapshot(15202)
    oracle = File.read!("test/fixtures/admin_mutations/sanitize_update.json") |> Jason.decode!()

    Repo.query!("UPDATE users SET settings=$1 WHERE id=15202", [oracle["before"]["settings"]],
      log: false
    )

    input = %{
      "email" => " A10B-UPDATED@example.invalid ",
      "password" => String.duplicate("ü", 128),
      "admin" => "1",
      "status" => "inactive",
      "current_password" => "wrong",
      "password_confirmation" => "wrong"
    }

    assert {:ok, 15202} = UserUpdate.call(c.actor, 15202, input, c.context)
    after_row = snapshot(15202)

    assert after_row["email"] == "a10b-updated@example.invalid" and after_row["admin"] and
             after_row["status"] == 0

    assert after_row["settings"] == oracle["after"]["settings"]
    valid = Bcrypt.verify_pass(String.duplicate("ü", 36), after_row["encrypted_password"])
    assert valid
    old_valid = Bcrypt.verify_pass(@password, after_row["encrypted_password"])
    refute old_valid

    assert is_nil(after_row["reset_password_token"]) and
             is_nil(after_row["reset_password_sent_at"])

    assert after_row["updated_at"] == "2026-10-04T10:00:00"

    for key <-
          ~w(unlock_token failed_attempts failed_otp_attempts otp_locked_at remember_created_at api_key active_until plan) do
      unchanged = before[key] == after_row[key]
      assert unchanged
    end

    before = snapshot(15202)
    assert {:invalid, _} = UserUpdate.call(c.actor, 15202, %{"email" => c.actor.email}, c.context)
    assert {:invalid, _} = UserUpdate.call(c.actor, 15202, %{"password" => "short"}, c.context)
    assert {:handoff, :target} = UserUpdate.call(c.actor, -1, %{}, c.context)
    assert snapshot(15202) == before

    Repo.query!("UPDATE users SET settings=$1 WHERE id=15202", [%{"photoprism_url" => 5}],
      log: false
    )

    before = snapshot(15202)

    assert {:handoff, :settings_callback} =
             UserUpdate.call(
               c.actor,
               15202,
               %{"email" => "a10b-unsupported@example.invalid"},
               c.context
             )

    assert snapshot(15202) == before
  end

  test "blank update preserves the persisted password hash", c do
    assert Code.ensure_loaded?(UserUpdate), "admin update must exist"

    for value <- [nil, "", "  ", "\t\n", "\u00a0", "\u2003"] do
      before = snapshot(15202)
      assert {:ok, 15202} = UserUpdate.call(c.actor, 15202, %{"password" => value}, c.context)
      unchanged = snapshot(15202) == before
      assert unchanged
    end

    assert {:ok, 15202} =
             UserUpdate.call(
               c.actor,
               15202,
               %{"email" => "a10b-blank-updated@example.invalid", "password" => "  "},
               c.context
             )

    same_hash = snapshot(15202)["encrypted_password"] == c.hash
    assert same_hash
  end

  test "own password change invalidates old Rails identity without bypass sign in", c do
    assert Code.ensure_loaded?(UserUpdate), "admin update must exist"
    session = %{"warden.user.user.key" => [[c.actor.id], binary_part(c.hash, 0, 29)]}
    assert Accounts.from_session(session, @now).id == c.actor.id

    assert {:blocked, _} =
             UserUpdate.call(c.actor, c.actor.id, %{"admin" => "0", "email" => "bad"}, c.context)

    assert {:blocked, _} = UserUpdate.call(c.actor, c.actor.id, %{"status" => 1}, c.context)

    assert {:ok, 15201} =
             UserUpdate.call(c.actor, c.actor.id, %{"password" => "a10b-new-password"}, c.context)

    accepted = not is_nil(Accounts.from_session(session, @now))
    refute accepted

    conn =
      c.actor.id
      |> RailsUser.session()
      |> Map.put("warden.user.user.key", session["warden.user.user.key"])

    raw =
      URI.encode_query(%{
        "authenticity_token" => DawarichWeb.RailsCsrf.masked_token(conn),
        "user[password]" => "a10b-http-self-password"
      })

    new_session =
      Map.put(conn, "warden.user.user.key", [
        [c.actor.id],
        binary_part(snapshot(15201)["encrypted_password"], 0, 29)
      ])

    request =
      Plug.Test.conn("PATCH", "/settings/users/15201", raw)
      |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(new_session))
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
      |> Plug.Conn.put_req_header("content-length", Integer.to_string(byte_size(raw)))
      |> Plug.Conn.put_req_header("accept", "text/html")
      |> DawarichWeb.AdminWrites.Users.call(action: :update, context: c.context)

    assert request.status == 302 and request.halted
    refute Map.has_key?(request.private.dawarich_rails_session_changes, "warden.user.user.key")

    {:ok, emitted_session} =
      Dawarich.RailsCookies.decrypt(
        request.resp_cookies["_dawarich_session"].value,
        "_dawarich_session",
        Dawarich.RailsSecret.fetch(),
        @now
      )

    same_identity = emitted_session["warden.user.user.key"] == new_session["warden.user.user.key"]
    assert same_identity
    accepted_emitted = not is_nil(Accounts.from_session(emitted_session, @now))
    refute accepted_emitted

    assert request.private.dawarich_rails_session_changes["flash"]["flashes"]["notice"] ==
             "User was successfully updated."

    Repo.query!("UPDATE users SET admin=false WHERE id=15201", [], log: false)
    before = snapshot(15202)

    assert {:handoff, :actor} =
             UserUpdate.call(
               c.actor,
               15202,
               %{"email" => "a10b-refused@example.invalid"},
               c.context
             )

    assert snapshot(15202) == before
  end

  test "equal cast role and status leave the whole older row unchanged", c do
    oracle = File.read!("test/fixtures/admin_mutations/noop_roles.json") |> Jason.decode!()
    assert oracle["before"] == oracle["after"]
    before = snapshot(15202)
    assert before["updated_at"] == "2026-10-03T10:00:00"

    assert {:ok, 15202} =
             UserUpdate.call(c.actor, 15202, %{"admin" => "0", "status" => "active"}, c.context)

    assert snapshot(15202) == before
  end

  defp snapshot(id) do
    [[row]] = Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [id], log: false).rows
    row
  end
end
