defmodule Dawarich.Auth.TwoFactor.SecretTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias Dawarich.Auth.{Account, AccountChanges}
  alias Dawarich.Auth.TwoFactor.Secret
  alias Dawarich.{ActiveRecordEncryption, Repo}

  @now ~U[2026-10-04 12:00:00.000000Z]
  @crypto "../../../fixtures/active_record_encryption.json"
          |> Path.expand(__DIR__)
          |> File.read!()
          |> Jason.decode!()
  @explicit Enum.find(@crypto["environments"], &(&1["name"] == "explicit keys"))
  @vars ~w(OTP_ENCRYPTION_PRIMARY_KEY OTP_ENCRYPTION_DETERMINISTIC_KEY OTP_ENCRYPTION_KEY_DERIVATION_SALT)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    hash = Bcrypt.hash_pwd_salt("a11c-synthetic-password", log_rounds: 4)

    [[id]] =
      Repo.query!(
        """
        INSERT INTO users(email,encrypted_password,api_key,status,settings,created_at,updated_at)
        VALUES($1,$2,'a11c-synthetic-key',1,$3,$4,$4) RETURNING id
        """,
        [
          "a11c-#{System.unique_integer([:positive])}@dawarich.test",
          hash,
          %{"timezone" => "Europe/Berlin"},
          @now
        ],
        log: false
      ).rows

    %{
      id: id,
      salt: binary_part(hash, 0, 29),
      context: %{self_hosted: true, clock: fn -> @now end}
    }
  end

  test "OTP secrets use existing Rails encryption only when management is available", c do
    assert Code.ensure_loaded?(Secret)
    env = @explicit["env"]
    assert Secret.available?(env)
    assert {:ok, key} = ActiveRecordEncryption.key(env)
    assert {:ok, ^key} = Secret.key(env)

    for var <- @vars, value <- [nil, "", " \t\n", <<160::utf8>>, <<0x3000::utf8>>] do
      absent = if is_nil(value), do: Map.delete(env, var), else: Map.put(env, var, value)
      refute Secret.available?(absent)
      assert {:handoff, :unavailable} = Secret.key(absent)
    end

    refute Secret.available?(%{})

    refute Secret.available?(%{
             "RAILS_ENV" => "production",
             "SECRET_KEY_BASE" => "synthetic-derived-key"
           })

    for vector <- @explicit["vectors"] do
      plaintext = vector["plaintext"] || Base.decode64!(vector["plaintext_base64"])
      assert Secret.decrypt(vector["ciphertext"], env) == {:ok, plaintext}
      assert {:ok, ciphertext} = Secret.encrypt(plaintext, env)
      assert ActiveRecordEncryption.decrypt(ciphertext, key) == {:ok, plaintext}
    end

    assert {:ok, nil} = Secret.decrypt(nil, env)
    assert {:handoff, :encryption} = Secret.decrypt("corrupt", env)
    assert {:handoff, :encryption} = Secret.decrypt("plaintext-should-never-pass", env)
    assert {:ok, ciphertext} = Secret.encrypt("a11c-private-plaintext", env)

    Repo.query!(
      "UPDATE users SET otp_secret=$1,otp_backup_codes=$2 WHERE id=$3",
      [ciphertext, ["a11c-private-backup-hash"], c.id],
      log: false
    )

    inspected = inspect(Repo.get!(Account, c.id))
    refute String.contains?(inspected, ciphertext)
    refute String.contains?(inspected, "a11c-private-backup-hash")
    refute String.contains?(inspected, "a11c-private-plaintext")

    log =
      capture_log([level: :debug], fn ->
        Secret.encrypt("a11c-private-plaintext", env)
        Secret.decrypt(ciphertext, env)
        Secret.actor(c.id, c.salt, c.context)
      end)

    for value <- [ciphertext, "a11c-private-plaintext", "a11c-private-backup-hash"] do
      refute String.contains?(log, value)
    end
  end

  test "management actor accepts OTP users without widening credential edits", c do
    assert Code.ensure_loaded?(Secret)
    fields = Account.__schema__(:fields)
    assert Enum.all?([:otp_secret, :otp_backup_codes, :consumed_timestep], &(&1 in fields))
    assert {:ok, %Account{}} = Secret.actor(c.id, c.salt, c.context)
    Repo.query!("UPDATE users SET otp_required_for_login=true WHERE id=$1", [c.id], log: false)
    assert {:ok, %Account{otp_required_for_login: true}} = Secret.actor(c.id, c.salt, c.context)
    assert {:handoff, :otp} = AccountChanges.actor(c.id, c.salt, c.context)
    assert {:handoff, :actor} = Secret.actor(-1, c.salt, c.context)
    assert {:handoff, :session} = Secret.actor(c.id, "stale-salt", c.context)
    assert {:handoff, :session} = Secret.actor(c.id, nil, c.context)
    hash = Bcrypt.hash_pwd_salt("a11c-another-synthetic-password", log_rounds: 4)

    [[foreign]] =
      Repo.query!(
        "INSERT INTO users(email,encrypted_password,status,settings,created_at,updated_at) VALUES($1,$2,1,$3,$4,$4) RETURNING id",
        ["a11c-foreign-#{System.unique_integer([:positive])}@dawarich.test", hash, %{}, @now],
        log: false
      ).rows

    assert {:handoff, :session} = Secret.actor(foreign, c.salt, c.context)
    assert {:handoff, :cloud} = Secret.actor(c.id, c.salt, %{c.context | self_hosted: false})
    assert {:handoff, :oidc} = Secret.actor(c.id, c.salt, Map.put(c.context, :oidc, true))

    for {field, value, reason} <- [
          {"deleted_at", @now, :actor},
          {"locked_at", @now, :locked},
          {"provider", "github", :provider},
          {"status", 3, :payment},
          {"email", "", :validation},
          {"email", " INVALID@EXAMPLE.TEST ", :validation},
          {"settings", %{"immich_url" => "https://a11c.example.test///"}, :settings_callback},
          {"settings", %{"maps" => %{"url" => " padded "}}, :settings_callback},
          {"settings", %{"photoprism_url" => 5}, :settings_callback}
        ] do
      [[original]] =
        Repo.query!("SELECT #{field} FROM users WHERE id=$1", [c.id], log: false).rows

      Repo.query!("UPDATE users SET #{field}=$1 WHERE id=$2", [value, c.id], log: false)
      assert {:handoff, ^reason} = Secret.actor(c.id, c.salt, c.context)
      Repo.query!("UPDATE users SET #{field}=$1 WHERE id=$2", [original, c.id], log: false)
    end
  end
end
