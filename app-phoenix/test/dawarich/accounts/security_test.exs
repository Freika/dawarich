defmodule Dawarich.Accounts.SecurityTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.{Accounts, Accounts.Scope}
  alias Dawarich.Test.RailsUser

  test "self security uses concurrent sandbox ownership" do
    assert __MODULE__.__ex_unit__(:config).async?
    assert Repo.query!("SELECT 1", [], log: false).rows == [[1]]
  end

  setup do
    env = %{
      "OTP_ENCRYPTION_PRIMARY_KEY" => "synthetic-primary",
      "OTP_ENCRYPTION_DETERMINISTIC_KEY" => "synthetic-deterministic",
      "OTP_ENCRYPTION_KEY_DERIVATION_SALT" => "synthetic-salt"
    }

    hash = Bcrypt.hash_pwd_salt("synthetic-password12", log_rounds: 4)

    user =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "scoped-security@example.test",
        encrypted_password: hash,
        api_key: "synthetic",
        admin: true,
        settings: %{}
      })

    %{
      id: user.id,
      hash: hash,
      scope: Scope.for_user(Accounts.get(user.id), "de"),
      proof: %{session_salt: String.slice(hash, 0, 29), pending: false},
      context: %{
        env: env,
        native: true,
        self_hosted: true,
        repo: Repo,
        backup_options: [log_rounds: 4]
      }
    }
  end

  defp manage(c, operation, fields \\ %{}, proof \\ nil),
    do:
      apply(Dawarich.Accounts.Security, :manage_two_factor, [
        c.scope,
        operation,
        fields,
        proof || c.proof,
        c.context
      ])

  test "HTTP 2FA rechecks stale salt deletion lock and pending state before writes", c do
    for changes <- [
          %{encrypted_password: Bcrypt.hash_pwd_salt("rotated-password12", log_rounds: 4)},
          %{deleted_at: DateTime.utc_now()},
          %{locked_at: DateTime.utc_now()}
        ] do
      user = Repo.get!(Dawarich.Auth.Account, c.id)
      Repo.update!(Ecto.Changeset.change(user, changes), log: false)
      refused? = match?({:handoff, _}, manage(c, :setup))
      assert refused?
      assert is_nil(Repo.get!(Dawarich.Auth.Account, c.id).otp_secret)
      user = Repo.get!(Dawarich.Auth.Account, c.id)

      Repo.update!(
        Ecto.Changeset.change(user, %{encrypted_password: c.hash, deleted_at: nil, locked_at: nil}),
        log: false
      )
    end

    refused? = match?({:handoff, _}, manage(c, :setup, %{}, %{c.proof | pending: true}))
    assert refused?
    refused? = match?({:handoff, _}, manage(c, :setup, %{"actor_id" => Integer.to_string(c.id)}))
    assert refused?
    refused? = match?({:handoff, _}, manage(c, :setup, %{}, %{c.proof | session_salt: "wrong"}))
    assert refused?
    assert is_nil(Repo.get!(Dawarich.Auth.Account, c.id).otp_secret)
  end

  test "self 2FA remains available after admin demotion with ordinary chrome", c do
    Repo.query!("UPDATE users SET admin=false,status=0 WHERE id=$1", [c.id], log: false)
    outcome = manage(c, :setup)
    successful? = match?({:ok, %{}}, outcome)
    assert successful?
    {:ok, result} = outcome
    assert result.kind == :verify
    assert Accounts.get(c.id).admin == false
    assert result.status == 0
    refute Map.has_key?(result, :user)
    refute Map.has_key?(result, :encrypted_password)
    assert is_binary(result.secret)
  end

  test "disable checks password before consuming a backup", c do
    secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    {:ok, ciphertext} = Dawarich.Auth.TwoFactor.Secret.encrypt(secret, c.context.env)
    {:ok, codes, hashes} = Dawarich.Auth.TwoFactor.BackupCodes.generate(log_rounds: 4)
    user = Repo.get!(Dawarich.Auth.Account, c.id)

    Repo.update!(
      Ecto.Changeset.change(user, %{
        otp_secret: ciphertext,
        otp_required_for_login: true,
        otp_backup_codes: hashes
      }),
      log: false
    )

    outcome = manage(c, :disable, %{"password" => "wrong", "otp_attempt" => hd(codes)})
    refused? = match?({:error, %{kind: :redirect, reason: :incorrect_password}}, outcome)
    assert refused?

    unchanged = Repo.get!(Dawarich.Auth.Account, c.id).otp_backup_codes == hashes
    assert unchanged
    assert Repo.get!(Dawarich.Auth.Account, c.id).otp_required_for_login
  end
end
