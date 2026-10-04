defmodule Dawarich.Auth.TwoFactor.ManagementTest.SecondSaveFailure do
  alias Dawarich.Repo
  defdelegate one(query, opts), to: Repo
  defdelegate query!(sql, params, opts), to: Repo
  defdelegate transaction(fun, opts), to: Repo

  def update!(changeset, opts) do
    if Map.has_key?(changeset.changes, :otp_backup_codes),
      do: raise("synthetic second-save failure"),
      else: Repo.update!(changeset, opts)
  end
end

defmodule Dawarich.Auth.TwoFactor.ManagementTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.TwoFactor.{BackupCodes, Management, Secret, Totp}
  alias Dawarich.Repo
  @now ~U[2026-10-04 12:00:00.000000Z]
  @crypto "../../../fixtures/active_record_encryption.json"
          |> Path.expand(__DIR__)
          |> File.read!()
          |> Jason.decode!()
  @explicit Enum.find(@crypto["environments"], &(&1["name"] == "explicit keys"))
  @source "../../../fixtures/auth/requests.json"
          |> Path.expand(__DIR__)
          |> File.read!()
          |> Jason.decode!()
  @oracle "../../../fixtures/auth/two_factor/requests.json"
          |> Path.expand(__DIR__)
          |> File.read!()
          |> Jason.decode!()

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    id = actor!()
    hash = @source["user_before"]["encrypted_password"]

    %{
      id: id,
      salt: binary_part(hash, 0, 29),
      context: %{self_hosted: true, env: @explicit["env"], clock: fn -> @now end}
    }
  end

  defp actor! do
    hash = @source["user_before"]["encrypted_password"]

    [[id]] =
      Repo.query!(
        """
        INSERT INTO users(email,encrypted_password,api_key,status,settings,failed_attempts,
          failed_otp_attempts,otp_locked_at,sign_in_count,reset_password_token,reset_password_sent_at,
          remember_created_at,created_at,updated_at)
        VALUES($1,$2,'a11c-synthetic-key',1,$3,2,3,$4,7,$1,$4,$4,$4,$4) RETURNING id
        """,
        [
          "a11c-management-#{System.unique_integer([:positive])}@dawarich.test",
          hash,
          %{"timezone" => "Europe/Berlin"},
          DateTime.add(@now, -86_400)
        ],
        log: false
      ).rows

    id
  end

  defp snapshot(id) do
    [[row]] = Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [id], log: false).rows
    row
  end

  defp seed(id, values) do
    Repo.get!(Account, id) |> Ecto.Changeset.change(values) |> Repo.update!(log: false)
  end

  test "Rails blank secrets reject verification and OTP disable without writes", c do
    rows =
      File.read!("test/fixtures/auth/two_factor/review_blank_secrets.json") |> Jason.decode!()

    for row <- rows do
      secret = row["secret"]
      ciphertext = if secret, do: elem(Secret.encrypt(secret, c.context.env), 1), else: nil
      hash = Bcrypt.hash_pwd_salt("a11c-review-backup", log_rounds: 4)

      seed(c.id,
        otp_secret: ciphertext,
        otp_required_for_login: true,
        otp_backup_codes: [hash],
        consumed_timestep: nil
      )

      before = snapshot(c.id)
      assert row["valid"] == false and row["unchanged"]
      assert Totp.verify(secret, row["code"], row["at"]) == :invalid
      result = Management.verify(c.id, c.salt, row["code"], c.context)

      assert match?({:error, %{reason: :invalid_verification_code}}, result) or
               match?({:handoff, :secret}, result)

      assert snapshot(c.id) == before

      assert {:error, %{reason: :provide_a_valid_two_factor_code_or_backup_code_to}} =
               Management.disable(c.id, c.salt, "safepassword12", row["code"], c.context)

      assert snapshot(c.id) == before

      assert {:ok, %{reason: :two_factor_authentication_disabled}} =
               Management.disable(c.id, c.salt, "safepassword12", "a11c-review-backup", c.context)

      refute Repo.get!(Account, c.id).otp_required_for_login
      assert is_nil(Repo.get!(Account, c.id).otp_backup_codes)
    end
  end

  test "web setup and verify preserve the source save sequence", c do
    assert Code.ensure_loaded?(Management)
    other = actor!()
    other_before = snapshot(other)
    initial = snapshot(c.id)
    assert {:ok, %{kind: :show}} = Management.show(c.id, c.salt, c.context)
    assert snapshot(c.id) == initial

    for index <- 1..3 do
      before = snapshot(c.id)
      context = Map.put(c.context, :secret_entropy, fn -> :binary.copy(<<index>>, 20) end)

      assert {:ok, %{kind: :verify, secret: secret, uri: uri}} =
               Management.setup(c.id, c.salt, context)

      expected = Totp.generate_secret(:binary.copy(<<index>>, 20))
      assert secret == expected
      user = Repo.get!(Account, c.id)
      assert Secret.decrypt(user.otp_secret, c.context.env) == {:ok, expected}
      assert uri == Totp.provisioning_uri(expected, user.email)
      after_row = snapshot(c.id)
      ignored = ~w(otp_secret updated_at)
      assert Map.drop(after_row, ignored) == Map.drop(before, ignored)
      assert before["otp_secret"] != after_row["otp_secret"]

      if index == 1 do
        seed(c.id,
          otp_required_for_login: true,
          consumed_timestep: 123,
          otp_backup_codes: [@source["user_before"]["encrypted_password"]]
        )
      end
    end

    {:ok, secret} = Secret.decrypt(Repo.get!(Account, c.id).otp_secret, c.context.env)
    seed(c.id, otp_required_for_login: false, consumed_timestep: nil, otp_backup_codes: nil)
    before = snapshot(c.id)

    assert {:error, %{kind: :verify, reason: :invalid_verification_code}} =
             Management.verify(c.id, c.salt, "not-a-code", c.context)

    assert snapshot(c.id) == before
    code = Totp.at(secret, DateTime.to_unix(@now))

    assert {:ok, %{kind: :backup_codes, codes: codes}} =
             Management.verify(c.id, c.salt, code, c.context)

    user = Repo.get!(Account, c.id)
    assert user.otp_required_for_login
    assert user.consumed_timestep == div(DateTime.to_unix(@now), 30)
    assert length(codes) == 10
    assert length(user.otp_backup_codes) == 10

    assert Enum.all?(Enum.zip(user.otp_backup_codes, codes), fn {hash, value} ->
             Bcrypt.verify_pass(value, hash)
           end)

    assert MapSet.disjoint?(MapSet.new(codes), MapSet.new(user.otp_backup_codes))
    ignored = ~w(otp_backup_codes otp_required_for_login consumed_timestep updated_at)
    assert Map.drop(snapshot(c.id), ignored) == Map.drop(before, ignored)
    before = snapshot(c.id)
    assert {:error, _} = Management.verify(c.id, c.salt, code, c.context)
    assert snapshot(c.id) == before

    seed(c.id,
      otp_required_for_login: false,
      consumed_timestep: nil,
      otp_backup_codes: nil,
      updated_at: DateTime.add(@now, -86_400)
    )

    context = Map.put(c.context, :repo, __MODULE__.SecondSaveFailure)

    assert_raise RuntimeError, "synthetic second-save failure", fn ->
      Management.verify(c.id, c.salt, code, context)
    end

    user = Repo.get!(Account, c.id)
    assert user.consumed_timestep == div(DateTime.to_unix(@now), 30)
    assert user.updated_at == @now
    refute user.otp_required_for_login
    assert is_nil(user.otp_backup_codes)
    assert snapshot(other) == other_before

    vector = Enum.find(@explicit["vectors"], &(&1["name"] == "140 bytes, not compressed"))
    consumed = Enum.find(@oracle, &(&1["name"] == "verify_good"))["after"]["consumed_timestep"]

    seed(c.id,
      otp_secret: vector["ciphertext"],
      consumed_timestep: consumed,
      otp_backup_codes: [@source["user_before"]["encrypted_password"]]
    )

    assert {:ok, []} =
             BackupCodes.consume(Repo.get!(Account, c.id).otp_backup_codes, "safepassword12")

    source_code = Totp.at(vector["plaintext"], DateTime.to_unix(@now))
    before = snapshot(c.id)
    assert {:error, _} = Management.verify(c.id, c.salt, source_code, c.context)
    assert snapshot(c.id) == before
    later_code = Totp.at(vector["plaintext"], DateTime.to_unix(@now) + 30)
    assert {:ok, _} = Management.verify(c.id, c.salt, later_code, c.context)
    assert Repo.get!(Account, c.id).consumed_timestep == consumed + 1
    seed(c.id, otp_backup_codes: [@source["user_before"]["encrypted_password"]])

    assert {:ok, _} =
             Management.disable(c.id, c.salt, "safepassword12", "safepassword12", c.context)

    assert is_nil(Repo.get!(Account, c.id).otp_backup_codes)
    before = snapshot(c.id)

    assert {:error, %{reason: :provide_a_valid_two_factor_code_or_backup_code_to}} =
             Management.disable(c.id, c.salt, "safepassword12", "safepassword12", c.context)

    assert snapshot(c.id) == before
  end

  test "web disable checks password before code and clears only source fields", c do
    assert Code.ensure_loaded?(Management) and function_exported?(Management, :disable, 5)
    other = actor!()
    other_before = snapshot(other)
    [[jobs_before]] = Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows
    {:ok, %{secret: secret}} = Management.setup(c.id, c.salt, c.context)
    code = Totp.at(secret, DateTime.to_unix(@now))
    {:ok, %{codes: codes}} = Management.verify(c.id, c.salt, code, c.context)
    future_code = Totp.at(secret, DateTime.to_unix(@now) + 30)

    for candidate <- [nil, "", "wrong-password"], otp <- [future_code, hd(codes)] do
      before = snapshot(c.id)

      assert {:error, %{reason: :incorrect_password}} =
               Management.disable(c.id, c.salt, candidate, otp, c.context)

      assert snapshot(c.id) == before
    end

    for otp <- [nil, "", "not-a-code", code] do
      before = snapshot(c.id)

      assert {:error, %{reason: :provide_a_valid_two_factor_code_or_backup_code_to}} =
               Management.disable(c.id, c.salt, "safepassword12", otp, c.context)

      assert snapshot(c.id) == before
    end

    for lock <- [DateTime.add(@now, -60), DateTime.add(@now, -7200)], kind <- [:totp, :backup] do
      {:ok, ciphertext} = Secret.encrypt(secret, c.context.env)
      {:ok, backup_codes, hashes} = BackupCodes.generate()

      seed(c.id,
        otp_secret: ciphertext,
        otp_backup_codes: hashes,
        otp_required_for_login: true,
        consumed_timestep: nil,
        otp_locked_at: lock
      )

      before = snapshot(c.id)
      otp = if kind == :totp, do: future_code, else: hd(backup_codes)

      assert {:ok, %{reason: :two_factor_authentication_disabled}} =
               Management.disable(c.id, c.salt, "safepassword12", otp, c.context)

      user = Repo.get!(Account, c.id)
      refute user.otp_required_for_login
      assert is_nil(user.otp_secret)
      assert is_nil(user.otp_backup_codes)
      timestep = if kind == :totp, do: div(DateTime.to_unix(@now), 30) + 1, else: nil
      assert user.consumed_timestep == timestep

      ignored =
        ~w(otp_secret otp_backup_codes otp_required_for_login consumed_timestep updated_at)

      assert Map.drop(snapshot(c.id), ignored) == Map.drop(before, ignored)
      before = snapshot(c.id)
      assert {:error, _} = Management.disable(c.id, c.salt, "safepassword12", otp, c.context)
      assert snapshot(c.id) == before
    end

    for backups <- [nil, []] do
      seed(c.id, otp_backup_codes: backups)
      before = snapshot(c.id)

      assert {:error, _} =
               Management.disable(c.id, c.salt, "safepassword12", "not-a-code", c.context)

      assert snapshot(c.id) == before
    end

    assert snapshot(other) == other_before
    [[jobs_after]] = Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows
    assert jobs_before == jobs_after
  end
end
