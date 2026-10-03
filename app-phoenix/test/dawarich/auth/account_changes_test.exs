defmodule Dawarich.Auth.AccountChangesTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.{Account, AccountChanges}
  alias Dawarich.Repo

  @now ~U[2026-10-04 00:00:00.000000Z]
  @password "a11rest-password-42"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    hash = Bcrypt.hash_pwd_salt(@password, log_rounds: 4)
    email = "a11rest-#{System.unique_integer([:positive])}@dawarich.test"

    [[id]] =
      Repo.query!(
        """
        INSERT INTO users(email,encrypted_password,api_key,status,settings,
          reset_password_token,reset_password_sent_at,failed_attempts,failed_otp_attempts,
          otp_locked_at,remember_created_at,sign_in_count,created_at,updated_at)
        VALUES($1,$2,'a11rest-key',1,$3,'a11rest-reset',$4,2,3,$4,$4,7,$4,$4) RETURNING id
        """,
        [email, hash, %{"timezone" => "Europe/Berlin"}, DateTime.add(@now, -86_400)],
        log: false
      ).rows

    %{
      id: id,
      email: email,
      salt: binary_part(hash, 0, 29),
      context: %{self_hosted: true, clock: fn -> @now end}
    }
  end

  test "rejects local updates without a valid current password before writes", c do
    assert Code.ensure_loaded?(AccountChanges)
    params = %{"email" => "a11rest-changed@dawarich.test"}

    for current <- [nil, "", "wrong-password"] do
      before = snapshot(c.id)
      input = if is_nil(current), do: params, else: Map.put(params, "current_password", current)
      assert {:error, render} = AccountChanges.update(c.id, c.salt, input, c.context)
      assert Enum.map(render.errors, &elem(&1, 0)) == [:current_password]
      assert render.email == params["email"]
      unchanged = snapshot(c.id) == before
      assert unchanged
      refute Map.has_key?(render, :current_password)
    end

    no_op = %{"email" => c.email, "current_password" => ""}
    assert {:error, _} = AccountChanges.update(c.id, c.salt, no_op, c.context)
    before = snapshot(c.id)

    assert {:ok, %Account{}} =
             AccountChanges.update(
               c.id,
               c.salt,
               %{no_op | "current_password" => @password},
               c.context
             )

    unchanged = snapshot(c.id) == before
    assert unchanged

    unsupported = [
      {"deleted_at", @now, :actor},
      {"locked_at", @now, :locked},
      {"provider", "github", :provider},
      {"otp_required_for_login", true, :otp},
      {"status", 3, :payment},
      {"settings", %{"immich_url" => "https://immich.a11rest.test///"}, :settings_callback},
      {"settings", %{"photoprism_url" => 5}, :settings_callback},
      {"settings", %{"maps" => %{"url" => " padded "}}, :settings_callback}
    ]

    for {field, value, reason} <- unsupported do
      [[original]] =
        Repo.query!("SELECT #{field} FROM users WHERE id=$1", [c.id], log: false).rows

      Repo.query!("UPDATE users SET #{field}=$1 WHERE id=$2", [value, c.id], log: false)
      before = snapshot(c.id)
      input = Map.put(params, "current_password", @password)
      assert {:handoff, ^reason} = AccountChanges.update(c.id, c.salt, input, c.context)
      unchanged = snapshot(c.id) == before
      assert unchanged
      Repo.query!("UPDATE users SET #{field}=$1 WHERE id=$2", [original, c.id], log: false)
    end

    before = snapshot(c.id)
    assert {:handoff, :actor} = AccountChanges.update(-1, c.salt, params, c.context)
    assert {:handoff, :session} = AccountChanges.update(c.id, "stale-salt", params, c.context)

    assert {:handoff, :cloud} =
             AccountChanges.update(c.id, c.salt, params, %{c.context | self_hosted: false})

    assert {:handoff, :oidc} =
             AccountChanges.update(c.id, c.salt, params, Map.put(c.context, :oidc, true))

    unchanged = snapshot(c.id) == before
    assert unchanged
  end

  defp snapshot(id) do
    [[row]] = Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [id], log: false).rows
    [[jobs]] = Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows
    [[mail_jobs]] = Repo.query!("SELECT count(*) FROM oban.oban_jobs", [], log: false).rows
    {row, jobs, mail_jobs}
  end
end
