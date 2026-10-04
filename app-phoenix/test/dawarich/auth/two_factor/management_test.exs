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
  end
end
