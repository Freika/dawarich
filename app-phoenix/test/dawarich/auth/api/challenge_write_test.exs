defmodule Dawarich.Auth.Api.ChallengeWriteTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.{Account, Api.Challenge, Api.ChallengeWrite, Api.ChallengeToken}
  alias Dawarich.Auth.TwoFactor.{Secret, Totp}
  alias Dawarich.{Redis, Repo, Test.RailsUser}
  @source "test/fixtures/auth/requests.json" |> File.read!() |> Jason.decode!()
  @crypto "test/fixtures/active_record_encryption.json" |> File.read!() |> Jason.decode!()
  @env Enum.find(@crypto["environments"], &(&1["name"] == "explicit keys"))["env"]
  @secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
  @now ~U[2026-10-04 12:00:00.000000Z]
  @id 75_710

  defmodule OrderedRepo do
    defdelegate one(query, opts), to: Repo
    defdelegate query!(query, params, opts), to: Repo

    def update!(changeset, opts) do
      kind = if Map.has_key?(changeset.changes, :failed_otp_attempts), do: :reset, else: :consume
      if Process.get(:a11f_fail) == kind, do: raise("a11f-#{kind}-failure")
      result = Repo.update!(changeset, opts)
      send(self(), {:write, kind})
      result
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    for spec <- Redis.cache_child_specs(), do: start_supervised!(spec)
    {:ok, ciphertext} = Secret.encrypt(@secret, @env)

    RailsUser.insert!(%{
      id: @id,
      email: "a11f-write@example.invalid",
      api_key: "synthetic fixture words",
      encrypted_password: @source["login"]["user"]["encrypted_password"],
      otp_secret: ciphertext,
      otp_required_for_login: true,
      otp_backup_codes: [@source["login"]["user"]["encrypted_password"]],
      subscription_source: 0,
      active_until: nil,
      failed_otp_attempts: 3,
      failed_attempts: 7,
      sign_in_count: 9,
      settings: %{},
      updated_at: DateTime.to_naive(DateTime.add(@now, -86_400))
    })

    jti = Ecto.UUID.generate()
    key = "otp_challenge:consumed:" <> jti

    on_exit(fn ->
      config = Application.fetch_env!(:dawarich, :redis)
      {:ok, conn} = Redix.start_link(config[:url], database: config[:cache_database])
      Redix.command(conn, ["DEL", key])
      GenServer.stop(conn)
    end)

    command = fn args ->
      if hd(args) == "SET" and Process.get(:a11f_fail) == :mark, do: raise("a11f-mark-failure")
      result = Redis.cache_command(args)
      if hd(args) == "SET", do: send(self(), {:write, :mark})
      result
    end

    context = %{
      self_hosted: true,
      oidc: false,
      timezone: "Etc/UTC",
      env:
        Map.put(
          @env,
          "JWT_SECRET_KEY",
          Dawarich.Auth.TwoFactor.Totp.generate_secret("a11f signing fixture")
        ),
      clock: fn -> @now end,
      jti: fn -> jti end,
      repo: OrderedRepo,
      cache_command: command
    }

    {:ok, token} = ChallengeToken.issue(@id, context)
    %{token: token, context: context, key: key}
  end

  test "API OTP success preserves source commit order partial effects and ignored NX loss", c do
    for kind <- [:totp, :backup] do
      reset(c.key)
      before = snapshot()

      code =
        if kind == :totp, do: Totp.at(@secret, DateTime.to_unix(@now)), else: "safepassword12"

      assert {:ok, prepared} = Challenge.prepare(c.token, code, c.context)
      assert {:ok, payload} = ChallengeWrite.commit(prepared, c.context)
      assert payload == prepared.payload
      assert writes() == [:consume, :mark, :reset]
      user = Repo.get!(Account, @id)
      assert user.failed_otp_attempts == 0 and user.otp_locked_at == nil
      assert user.updated_at == @now
      assert user.consumed_timestep == if(kind == :totp, do: div(DateTime.to_unix(@now), 30))

      assert user.otp_backup_codes ==
               if(kind == :backup, do: [], else: prepared.user.otp_backup_codes)

      assert Map.drop(
               snapshot(),
               ~w(consumed_timestep otp_backup_codes failed_otp_attempts otp_locked_at updated_at)
             ) ==
               Map.drop(
                 before,
                 ~w(consumed_timestep otp_backup_codes failed_otp_attempts otp_locked_at updated_at)
               )
    end

    for failure <- [:consume, :mark, :reset] do
      reset(c.key)
      code = Totp.at(@secret, DateTime.to_unix(@now))
      assert {:ok, prepared} = Challenge.prepare(c.token, code, c.context)
      Process.put(:a11f_fail, failure)

      try do
        assert_raise RuntimeError, "a11f-#{failure}-failure", fn ->
          ChallengeWrite.commit(prepared, c.context)
        end
      after
        Process.delete(:a11f_fail)
      end

      user = Repo.get!(Account, @id)

      assert user.consumed_timestep ==
               if(failure != :consume, do: div(DateTime.to_unix(@now), 30))

      assert user.failed_otp_attempts == 3
      assert {:ok, marker} = Redis.cache_command(["GET", c.key])
      assert is_binary(marker) == (failure == :reset)
      writes()
    end

    for lost <- [:nx, :redis_error] do
      reset(c.key)

      assert {:ok, prepared} =
               Challenge.prepare(c.token, Totp.at(@secret, DateTime.to_unix(@now)), c.context)

      context =
        if lost == :nx do
          Redis.cache_command([
            "SET",
            c.key,
            Dawarich.RailsCache.Wire.encode_boolean(false, expires_at: nil)
          ])

          c.context
        else
          Map.put(c.context, :cache_command, fn _ -> {:error, :unavailable} end)
        end

      assert {:ok, _} = ChallengeWrite.commit(prepared, context)
      assert Repo.get!(Account, @id).failed_otp_attempts == 0
      assert Repo.get!(Account, @id).consumed_timestep == div(DateTime.to_unix(@now), 30)
      writes()
    end
  end

  defp snapshot do
    [[row]] = Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [@id], log: false).rows
    row
  end

  defp reset(key) do
    Repo.get!(Account, @id)
    |> Ecto.Changeset.change(
      consumed_timestep: nil,
      failed_otp_attempts: 3,
      otp_locked_at: nil,
      otp_backup_codes: [@source["login"]["user"]["encrypted_password"]],
      updated_at: DateTime.add(@now, -86_400)
    )
    |> Repo.update!(log: false)

    Redis.cache_command(["DEL", key])
  end

  defp writes do
    receive do
      {:write, kind} -> [kind | writes()]
    after
      0 -> []
    end
  end
end
