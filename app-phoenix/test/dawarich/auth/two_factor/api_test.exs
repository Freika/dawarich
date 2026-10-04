defmodule Dawarich.Auth.TwoFactor.ApiTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.TwoFactor.{Api, BackupCodes, Secret, Totp}
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
        VALUES($1,$2,'a4otp-api-synthetic-key',0,$3,2,3,$4,7,$4,$4) RETURNING id
        """,
        [
          "a4otp-api-#{System.unique_integer([:positive])}@example.invalid",
          hash,
          %{"timezone" => "Europe/Berlin"},
          DateTime.add(@now, -86_400)
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

  test "API setup checks availability before password and rejects enabled accounts after password",
       c do
    seed(c.id, otp_required_for_login: true)
    before = snapshot(c.id)

    assert {:ok, 503, {:object, [{"error", "two_factor_not_available"}]}} =
             Api.run(:setup, c.id, %{"password" => "wrong"}, %{c.context | env: %{}})

    assert {:ok, 401,
            {:object,
             [{"error", "password_required"}, {"message", "Provide your current password."}]}} =
             Api.run(:setup, c.id, %{"password" => "wrong"}, c.context)

    assert {:ok, 409,
            {:object,
             [
               {"error", "two_factor_already_enabled"},
               {"message", "Disable 2FA first to re-provision the secret."}
             ]}} =
             Api.run(:setup, c.id, %{"password" => "safepassword12"}, c.context)

    assert snapshot(c.id) == before
  end

  test "API setup rotates ciphertext without enabling or clearing existing state", c do
    seed(c.id,
      consumed_timestep: 123,
      otp_backup_codes: [Repo.get!(Account, c.id).encrypted_password]
    )

    [[jobs]] = Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows

    for index <- 1..2 do
      before = snapshot(c.id)
      entropy = :binary.copy(<<index>>, 20)
      context = Map.put(c.context, :secret_entropy, fn -> entropy end)

      assert {:ok, 200, {:object, [{"provisioning_uri", uri}, {"secret", secret}]}} =
               Api.run(:setup, c.id, %{"password" => "safepassword12"}, context)

      user = Repo.get!(Account, c.id)
      assert secret == Totp.generate_secret(entropy)
      assert Secret.decrypt(user.otp_secret, @env) == {:ok, secret}
      assert uri == Totp.provisioning_uri(secret, user.email)
      assert user.updated_at == @now
      refute user.otp_required_for_login
      assert user.otp_secret != before["otp_secret"]

      assert Map.drop(snapshot(c.id), ~w(otp_secret updated_at)) ==
               Map.drop(before, ~w(otp_secret updated_at))
    end

    assert Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows == [[jobs]]
  end

  test "API confirm enables and replaces backups without consuming timestep", c do
    secret = Totp.generate_secret(:binary.copy(<<2>>, 20))
    {:ok, ciphertext} = Secret.encrypt(secret, @env)
    {:ok, old_codes, hashes} = BackupCodes.generate()
    seed(c.id, otp_secret: ciphertext, otp_backup_codes: hashes, consumed_timestep: 123)
    code = Totp.at(secret, DateTime.to_unix(@now))

    for _ <- 1..2 do
      before = snapshot(c.id)

      assert {:ok, 200, {:object, [{"backup_codes", codes}]}} =
               Api.run(
                 :confirm,
                 c.id,
                 %{"password" => "safepassword12", "otp_code" => code},
                 c.context
               )

      user = Repo.get!(Account, c.id)
      assert user.otp_required_for_login
      assert length(codes) == 10 and length(Enum.uniq(codes)) == 10
      assert length(user.otp_backup_codes) == 10
      assert user.otp_backup_codes != before["otp_backup_codes"]
      assert Enum.all?(codes, &Regex.match?(~r/\A[0-9a-f]{24}\z/, &1))

      assert Enum.all?(Enum.zip(codes, user.otp_backup_codes), fn {value, hash} ->
               Bcrypt.verify_pass(value, hash)
             end)

      assert BackupCodes.consume(user.otp_backup_codes, hd(old_codes)) == :invalid

      assert Map.drop(snapshot(c.id), ~w(otp_required_for_login otp_backup_codes updated_at)) ==
               Map.drop(before, ~w(otp_required_for_login otp_backup_codes updated_at))
    end
  end

  test "API confirm accepts a previously consumed timestep as Rails does", c do
    secret = Totp.generate_secret(:binary.copy(<<2>>, 20))
    {:ok, ciphertext} = Secret.encrypt(secret, @env)
    timestep = div(DateTime.to_unix(@now), 30)
    seed(c.id, otp_secret: ciphertext, consumed_timestep: timestep)
    before = snapshot(c.id)
    code = Totp.at(secret, DateTime.to_unix(@now))

    assert {:ok, 200, {:object, [{"backup_codes", _}]}} =
             Api.run(
               :confirm,
               c.id,
               %{"password" => "safepassword12", "otp_code" => code},
               c.context
             )

    assert Repo.get!(Account, c.id).consumed_timestep == timestep

    assert Map.drop(snapshot(c.id), ~w(otp_required_for_login otp_backup_codes updated_at)) ==
             Map.drop(before, ~w(otp_required_for_login otp_backup_codes updated_at))
  end

  test "API invalid confirm leaves the complete actor row unchanged", c do
    secret = Totp.generate_secret(:binary.copy(<<2>>, 20))
    {:ok, ciphertext} = Secret.encrypt(secret, @env)
    code = Totp.at(secret, DateTime.to_unix(@now))

    for {secret_field, candidate} <- [
          {nil, code},
          {ciphertext, nil},
          {ciphertext, "bad"},
          {ciphertext, Totp.at(secret, DateTime.to_unix(@now) - 60)}
        ] do
      seed(c.id, otp_secret: secret_field)
      before = snapshot(c.id)

      assert {:ok, 422, {:object, [{"error", "invalid_otp"}]}} =
               Api.run(
                 :confirm,
                 c.id,
                 %{"password" => "safepassword12", "otp_code" => candidate},
                 c.context
               )

      assert {:ok, 401, _} =
               Api.run(
                 :confirm,
                 c.id,
                 %{"password" => "wrong", "otp_code" => candidate},
                 c.context
               )

      assert snapshot(c.id) == before
    end
  end

  test "API regeneration replaces ten compatible hashes even with no secret or enabled flag", c do
    {:ok, ciphertext} = Secret.encrypt(Totp.generate_secret(:binary.copy(<<3>>, 20)), @env)

    for {secret, enabled} <- [{nil, false}, {ciphertext, false}, {ciphertext, true}] do
      {:ok, old_codes, hashes} = BackupCodes.generate()

      seed(c.id,
        otp_secret: secret,
        otp_required_for_login: enabled,
        otp_backup_codes: hashes,
        consumed_timestep: 123
      )

      before = snapshot(c.id)

      assert {:ok, 200, {:object, [{"backup_codes", codes}]}} =
               Api.run(
                 :backup_codes,
                 c.id,
                 %{"password" => "safepassword12", "otp_code" => "ignored"},
                 c.context
               )

      user = Repo.get!(Account, c.id)
      assert length(codes) == 10 and length(Enum.uniq(codes)) == 10
      assert length(user.otp_backup_codes) == 10
      assert Enum.all?(codes, &Regex.match?(~r/\A[0-9a-f]{24}\z/, &1))

      assert Enum.all?(Enum.zip(codes, user.otp_backup_codes), fn {value, hash} ->
               Bcrypt.verify_pass(value, hash)
             end)

      assert MapSet.disjoint?(MapSet.new(user.otp_backup_codes), MapSet.new(hashes))
      assert BackupCodes.consume(user.otp_backup_codes, hd(old_codes)) == :invalid
      assert {:ok, remaining} = BackupCodes.consume(user.otp_backup_codes, hd(codes))
      assert length(remaining) == 9
      assert BackupCodes.consume(remaining, hd(codes)) == :invalid

      assert Map.drop(snapshot(c.id), ~w(otp_backup_codes updated_at)) ==
               Map.drop(before, ~w(otp_backup_codes updated_at))
    end
  end
end
