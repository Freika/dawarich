defmodule Dawarich.Auth.TwoFactor.ApiTest.SecondSaveFailure do
  alias Dawarich.Repo
  defdelegate one(query, opts), to: Repo
  defdelegate query!(sql, params, opts), to: Repo
  defdelegate transaction(fun, opts), to: Repo

  def update!(changeset, opts) do
    if Map.has_key?(changeset.changes, :otp_secret) and is_nil(changeset.changes.otp_secret),
      do: raise("synthetic API clear-save failure"),
      else: Repo.update!(changeset, opts)
  end
end

defmodule Dawarich.Auth.TwoFactor.ApiTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.TwoFactor.{Api, BackupCodes, Management, Secret, Totp}
  alias Dawarich.Repo

  @now ~U[2026-10-04 12:00:00.000000Z]
  @crypto "../../../fixtures/active_record_encryption.json"
          |> Path.expand(__DIR__)
          |> File.read!()
          |> Jason.decode!()
  @env Enum.find(@crypto["environments"], &(&1["name"] == "explicit keys"))["env"]

  @web_oracle "../../../fixtures/auth/two_factor/requests.json"
              |> Path.expand(__DIR__)
              |> File.read!()
              |> Jason.decode!()
  @api_oracle "../../../fixtures/api_account/golden.json"
              |> Path.expand(__DIR__)
              |> File.read!()
              |> Jason.decode!()

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

  test "API two-factor NUL inputs replay before actor lookup or writes", c do
    before = snapshot(c.id)
    context = Map.put(c.context, :repo, :must_not_load_actor)

    for action <- [:setup, :confirm, :backup_codes, :destroy],
        params <- [
          %{"password" => "wrong" <> <<0>> <> "suffix"},
          %{"password" => "safepassword12" <> <<0>> <> "suffix"},
          %{"password" => "safepassword12", "otp_code" => "safepassword12" <> <<0>> <> "suffix"}
        ] do
      assert {:replay, :parameters} = Api.run(action, c.id, params, context)
      assert snapshot(c.id) == before
    end
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

  test "web setup feeds API confirm and web disable consumes API backups once", c do
    web = Enum.find(@web_oracle, &(&1["name"] == "disable_backup"))
    context = Map.put(c.context, :backup_options, log_rounds: 4)
    salt = binary_part(Repo.get!(Account, c.id).encrypted_password, 0, 29)
    {:ok, lock, _} = DateTime.from_iso8601(web["before"]["otp_locked_at"])

    seed(c.id, consumed_timestep: 123, otp_locked_at: lock)
    before = snapshot(c.id)
    assert {:ok, %{secret: secret}} = Management.setup(c.id, salt, context)

    assert Map.drop(snapshot(c.id), ~w(otp_secret updated_at)) ==
             Map.drop(before, ~w(otp_secret updated_at))

    code = Totp.at(secret, DateTime.to_unix(@now))
    before = snapshot(c.id)

    assert {:ok, 200, {:object, [{"backup_codes", codes}]}} =
             Api.run(
               :confirm,
               c.id,
               %{"password" => "safepassword12", "otp_code" => code},
               context
             )

    assert_confirm_preserved(before, snapshot(c.id))

    assert length(codes) ==
             length(Enum.find(@web_oracle, &(&1["name"] == "verify_good"))["after"]["backups"])

    assert_raise RuntimeError, "synthetic API clear-save failure", fn ->
      Management.disable(
        c.id,
        salt,
        "safepassword12",
        hd(codes),
        Map.put(context, :repo, __MODULE__.SecondSaveFailure)
      )
    end

    spent = snapshot(c.id)
    assert length(spent["otp_backup_codes"]) == length(codes) - 1
    assert spent["consumed_timestep"] == before["consumed_timestep"]

    assert {:ok, 401, _} =
             Api.run(
               :destroy,
               c.id,
               %{"password" => "safepassword12", "otp_code" => hd(codes)},
               context
             )

    assert snapshot(c.id) == spent

    assert {:ok, %{user: disabled}} =
             Management.disable(c.id, salt, "safepassword12", Enum.at(codes, 1), context)

    assert disabled.otp_backup_codes == web["after"]["backups"]
    assert disabled.otp_secret == web["after"]["secret"]
    assert disabled.otp_required_for_login == web["after"]["enabled"]
    assert disabled.failed_attempts == web["after"]["failed_attempts"]
    assert disabled.failed_otp_attempts == web["after"]["failed_otp_attempts"]
    assert disabled.otp_locked_at == lock
    assert disabled.consumed_timestep == before["consumed_timestep"]
    cleared = snapshot(c.id)

    assert {:ok, 401, _} =
             Api.run(
               :destroy,
               c.id,
               %{"password" => "safepassword12", "otp_code" => Enum.at(codes, 1)},
               context
             )

    assert snapshot(c.id) == cleared
  end

  test "API setup feeds web verify and API confirm preserves web consumption before API destroy",
       c do
    web = Enum.find(@web_oracle, &(&1["name"] == "verify_good"))["after"]
    api = Enum.find(@api_oracle["cases"], &(&1["name"] == "otp_destroy_backup"))
    api_clear = hd(api["after"]["users"])
    context = Map.put(c.context, :backup_options, log_rounds: 4)
    salt = binary_part(Repo.get!(Account, c.id).encrypted_password, 0, 29)
    {:ok, lock, _} = DateTime.from_iso8601(web["otp_locked_at"])
    seed(c.id, otp_locked_at: lock)

    assert {:ok, 200, {:object, setup}} =
             Api.run(:setup, c.id, %{"password" => "safepassword12"}, context)

    secret = Map.new(setup)["secret"]
    code = Totp.at(secret, DateTime.to_unix(@now))

    assert {:ok, %{user: verified, codes: web_codes}} =
             Management.verify(c.id, salt, code, context)

    assert verified.consumed_timestep == web["consumed_timestep"]
    assert verified.failed_attempts == web["failed_attempts"]
    assert verified.failed_otp_attempts == web["failed_otp_attempts"]
    assert verified.otp_locked_at == lock
    before = snapshot(c.id)

    assert {:ok, 200, {:object, [{"backup_codes", codes}]}} =
             Api.run(
               :confirm,
               c.id,
               %{"password" => "safepassword12", "otp_code" => code},
               context
             )

    assert_confirm_preserved(before, snapshot(c.id))

    assert BackupCodes.consume(Repo.get!(Account, c.id).otp_backup_codes, hd(web_codes)) ==
             :invalid

    before = snapshot(c.id)

    assert {:ok, 401, _} =
             Api.run(
               :destroy,
               c.id,
               %{"password" => "safepassword12", "otp_code" => code},
               context
             )

    assert snapshot(c.id) == before

    assert_raise RuntimeError, "synthetic API clear-save failure", fn ->
      Api.run(
        :destroy,
        c.id,
        %{"password" => "safepassword12", "otp_code" => hd(codes)},
        Map.put(context, :repo, __MODULE__.SecondSaveFailure)
      )
    end

    spent = snapshot(c.id)
    assert length(spent["otp_backup_codes"]) == length(codes) - 1

    assert {:error, %{reason: :provide_a_valid_two_factor_code_or_backup_code_to}} =
             Management.disable(c.id, salt, "safepassword12", hd(codes), context)

    assert snapshot(c.id) == spent

    assert {:ok, 200, _} =
             Api.run(
               :destroy,
               c.id,
               %{"password" => "safepassword12", "otp_code" => Enum.at(codes, 1)},
               context
             )

    disabled = Repo.get!(Account, c.id)
    assert disabled.otp_backup_codes == api_clear["otp_backup_codes"]
    assert disabled.otp_secret == api_clear["otp_secret"]
    assert disabled.otp_required_for_login == api_clear["otp_required_for_login"]
    assert disabled.consumed_timestep == web["consumed_timestep"]
    assert disabled.failed_attempts == web["failed_attempts"]
    assert disabled.failed_otp_attempts == web["failed_otp_attempts"]
    assert disabled.otp_locked_at == lock
    cleared = snapshot(c.id)

    assert {:error, _} =
             Management.disable(c.id, salt, "safepassword12", Enum.at(codes, 1), context)

    assert snapshot(c.id) == cleared
  end

  defp assert_confirm_preserved(before, after_row) do
    source = Enum.find(@api_oracle["cases"], &(&1["name"] == "otp_confirm_consumed"))

    ["users", [source_before | _]] =
      Enum.find(@api_oracle["setups"][source["setup"]], &(hd(&1) == "users"))

    preserved = ~w(consumed_timestep failed_attempts failed_otp_attempts otp_locked_at)
    assert Map.take(hd(source["after"]["users"]), preserved) == Map.take(source_before, preserved)
    assert Map.take(after_row, preserved) == Map.take(before, preserved)

    assert Map.drop(after_row, ~w(otp_required_for_login otp_backup_codes updated_at)) ==
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

  test "API disable rejects wrong password without spending a usable code", c do
    secret = Totp.generate_secret(:binary.copy(<<4>>, 20))
    {:ok, ciphertext} = Secret.encrypt(secret, @env)
    {:ok, codes, hashes} = BackupCodes.generate()
    seed(c.id, otp_secret: ciphertext, otp_required_for_login: true, otp_backup_codes: hashes)
    code = Totp.at(secret, DateTime.to_unix(@now))

    for password <- [nil, "", "wrong"], candidate <- [code, hd(codes)] do
      seed(c.id,
        otp_secret: ciphertext,
        otp_required_for_login: true,
        otp_backup_codes: hashes,
        consumed_timestep: nil
      )

      before = snapshot(c.id)

      assert {:ok, 401,
              {:object,
               [{"error", "password_required"}, {"message", "Provide your current password."}]}} =
               Api.run(
                 :destroy,
                 c.id,
                 %{"password" => password, "otp_code" => candidate},
                 c.context
               )

      assert snapshot(c.id) == before
      assert {:ok, _} = Totp.verify(secret, code, DateTime.to_unix(@now))
      assert {:ok, _} = BackupCodes.consume(Repo.get!(Account, c.id).otp_backup_codes, hd(codes))

      assert {:ok, 200, _} =
               Api.run(
                 :destroy,
                 c.id,
                 %{"password" => "safepassword12", "otp_code" => candidate},
                 c.context
               )
    end
  end

  test "API disable consumes TOTP or one backup then clears to an empty array", c do
    secret = Totp.generate_secret(:binary.copy(<<4>>, 20))
    {:ok, ciphertext} = Secret.encrypt(secret, @env)
    {:ok, codes, hashes} = BackupCodes.generate()
    now = DateTime.to_unix(@now)
    current = Totp.at(secret, now)

    seed(c.id,
      otp_secret: ciphertext,
      otp_required_for_login: true,
      otp_backup_codes: hashes,
      consumed_timestep: div(now, 30)
    )

    for candidate <- [nil, "", " ", "bad", current] do
      before = snapshot(c.id)

      assert {:ok, 401,
              {:object,
               [
                 {"error", "otp_required"},
                 {"message", "Provide a valid two-factor code (or backup code) to disable 2FA."}
               ]}} =
               Api.run(
                 :destroy,
                 c.id,
                 %{"password" => "safepassword12", "otp_code" => candidate},
                 c.context
               )

      assert snapshot(c.id) == before
    end

    for {candidate, timestep} <- [
          {" " <> current <> " ", div(now, 30)},
          {Totp.at(secret, now - 30), div(now, 30) - 1},
          {Totp.at(secret, now + 30), div(now, 30) + 1},
          {hd(codes), nil}
        ] do
      seed(c.id,
        otp_secret: ciphertext,
        otp_required_for_login: true,
        otp_backup_codes: hashes,
        consumed_timestep: nil
      )

      before = snapshot(c.id)

      assert {:ok, 200, {:object, [{"message", "Two-factor authentication disabled"}]}} =
               Api.run(
                 :destroy,
                 c.id,
                 %{"password" => "safepassword12", "otp_code" => candidate},
                 c.context
               )

      user = Repo.get!(Account, c.id)
      assert is_nil(user.otp_secret) and user.otp_required_for_login == false
      assert user.otp_backup_codes == []
      assert user.consumed_timestep == timestep

      assert Map.drop(
               snapshot(c.id),
               ~w(otp_secret otp_required_for_login otp_backup_codes consumed_timestep updated_at)
             ) ==
               Map.drop(
                 before,
                 ~w(otp_secret otp_required_for_login otp_backup_codes consumed_timestep updated_at)
               )

      after_row = snapshot(c.id)

      assert {:ok, 401, _} =
               Api.run(
                 :destroy,
                 c.id,
                 %{"password" => "safepassword12", "otp_code" => candidate},
                 c.context
               )

      assert snapshot(c.id) == after_row
    end
  end

  test "API disable keeps consumption when the clear save fails", c do
    secret = Totp.generate_secret(:binary.copy(<<4>>, 20))
    {:ok, ciphertext} = Secret.encrypt(secret, @env)
    {:ok, codes, hashes} = BackupCodes.generate()
    code = Totp.at(secret, DateTime.to_unix(@now))

    for kind <- [:totp, :backup] do
      seed(c.id,
        otp_secret: ciphertext,
        otp_required_for_login: true,
        otp_backup_codes: hashes,
        consumed_timestep: nil,
        updated_at: DateTime.add(@now, -86_400)
      )

      before = snapshot(c.id)
      candidate = if kind == :totp, do: code, else: hd(codes)
      context = Map.put(c.context, :repo, __MODULE__.SecondSaveFailure)

      assert_raise RuntimeError, "synthetic API clear-save failure", fn ->
        Api.run(
          :destroy,
          c.id,
          %{"password" => "safepassword12", "otp_code" => candidate},
          context
        )
      end

      user = Repo.get!(Account, c.id)
      assert user.otp_secret == ciphertext and user.otp_required_for_login
      assert user.updated_at == @now

      if kind == :totp do
        assert user.consumed_timestep == div(DateTime.to_unix(@now), 30)
        assert user.otp_backup_codes == hashes
      else
        assert user.consumed_timestep == nil
        assert length(user.otp_backup_codes) == 9
        assert BackupCodes.consume(user.otp_backup_codes, candidate) == :invalid
      end

      assert Map.drop(snapshot(c.id), ~w(consumed_timestep otp_backup_codes updated_at)) ==
               Map.drop(before, ~w(consumed_timestep otp_backup_codes updated_at))
    end
  end
end
