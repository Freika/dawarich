defmodule Dawarich.Auth.TwoFactor.ApiActorTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.TwoFactor.{ApiActor, Secret, Totp}
  alias Dawarich.Repo

  @now ~U[2026-10-04 12:00:00.000000Z]
  @crypto "../../../fixtures/active_record_encryption.json"
          |> Path.expand(__DIR__)
          |> File.read!()
          |> Jason.decode!()
  @env Enum.find(@crypto["environments"], &(&1["name"] == "explicit keys"))["env"]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    hash = Bcrypt.hash_pwd_salt("safepassword12", log_rounds: 4)

    [[id]] =
      Repo.query!(
        """
        INSERT INTO users(email,encrypted_password,api_key,status,settings,failed_attempts,
          failed_otp_attempts,otp_locked_at,sign_in_count,created_at,updated_at)
        VALUES($1,$2,'a4otp-actor-synthetic-key',0,$3,2,3,$4,7,$4,$4) RETURNING id
        """,
        [
          "a4otp-actor-#{System.unique_integer([:positive])}@example.invalid",
          hash,
          %{"timezone" => "Europe/Berlin"},
          @now
        ],
        log: false
      ).rows

    %{id: id, context: %{self_hosted: true, env: @env, clock: fn -> @now end}}
  end

  defp seed(id, fields),
    do: Repo.get!(Account, id) |> Ecto.Changeset.change(fields) |> Repo.update!(log: false)

  defp snapshot(id) do
    [[row]] = Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [id], log: false).rows
    row
  end

  test "API actor admits inactive and OTP accounts without a session salt", c do
    {:ok, ciphertext} = Secret.encrypt(Totp.generate_secret(), @env)

    for enabled <- [false, true] do
      seed(c.id,
        otp_required_for_login: enabled,
        otp_secret: ciphertext,
        locked_at: @now,
        otp_backup_codes: []
      )

      before = snapshot(c.id)
      assert {:ok, user} = ApiActor.load(c.id, c.context)
      assert user.id == c.id and user.status == 0
      assert user.otp_required_for_login == enabled
      assert user.settings == %{"timezone" => "Europe/Berlin"}
      assert snapshot(c.id) == before
    end
  end

  test "API actor rejects deleted or callback-unsafe rows before writes", c do
    assert {:replay, _} = ApiActor.load(-1, c.context)
    assert {:replay, _} = ApiActor.load(c.id, %{c.context | self_hosted: false})

    for fields <- [
          [deleted_at: @now],
          [provider: "google"],
          [email: "legacy@example.invalid "],
          [encrypted_password: "legacy-digest"],
          [otp_secret: "corrupt-ciphertext"],
          [otp_backup_codes: ["not-a-bcrypt-hash"]]
        ] do
      original = Repo.get!(Account, c.id)
      seed(c.id, fields)
      before = snapshot(c.id)
      assert {:replay, _} = ApiActor.load(c.id, c.context)
      assert snapshot(c.id) == before
      seed(c.id, Enum.map(fields, fn {key, _} -> {key, Map.fetch!(original, key)} end))
    end

    for settings <- [
          [],
          %{"immich_url" => "https://example.invalid/"},
          %{"maps" => %{"url" => " map "}},
          %{"photoprism_url" => 12}
        ] do
      Repo.query!("UPDATE users SET settings=$1 WHERE id=$2", [settings, c.id], log: false)
      before = snapshot(c.id)
      assert {:replay, _} = ApiActor.load(c.id, c.context)
      assert snapshot(c.id) == before
    end

    Repo.query!("UPDATE users SET settings=$1 WHERE id=$2", [%{}, c.id], log: false)
    {:ok, ciphertext} = Secret.encrypt("not-valid-base32!", @env)
    seed(c.id, otp_secret: ciphertext)
    before = snapshot(c.id)
    assert {:replay, _} = ApiActor.load(c.id, c.context)
    assert snapshot(c.id) == before
  end

  test "API password verification has Devise bytes and no login effects", c do
    [[jobs]] = Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows
    {:ok, user} = ApiActor.load(c.id, c.context)
    before = snapshot(c.id)
    assert ApiActor.password_valid?(user, "safepassword12")

    for password <- [nil, "", " ", "wrong", "safepassword12 "] do
      refute ApiActor.password_valid?(user, password)
    end

    for password <- [
          String.duplicate("x", 71) <> "yz",
          String.duplicate("x", 71) <> "üx",
          " spaced password "
        ] do
      bytes = binary_part(password, 0, min(byte_size(password), 72))
      hash = Bcrypt.hash_pwd_salt(bytes, log_rounds: 4)
      seed(c.id, encrypted_password: hash)
      {:ok, user} = ApiActor.load(c.id, c.context)
      prior = snapshot(c.id)
      assert ApiActor.password_valid?(user, password)
      refute ApiActor.password_valid?(user, "wrong")
      assert snapshot(c.id) == prior
    end

    assert Map.drop(snapshot(c.id), ["encrypted_password"]) ==
             Map.drop(before, ["encrypted_password"])

    assert Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows == [[jobs]]
  end
end
