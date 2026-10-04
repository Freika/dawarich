defmodule Dawarich.Auth.TwoFactor.ApiTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.TwoFactor.{Api, Secret, Totp}
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
end
