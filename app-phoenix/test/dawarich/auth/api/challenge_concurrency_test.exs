defmodule Dawarich.Auth.Api.ChallengeConcurrencyTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.{Account, Api.Challenge, Api.ChallengeWrite, Api.ChallengeToken}
  alias Dawarich.Auth.TwoFactor.{Secret, Totp}
  alias Dawarich.{Redis, Repo, Test.RailsUser}
  @source "test/fixtures/auth/requests.json" |> File.read!() |> Jason.decode!()
  @races "test/fixtures/auth/api_auth/races.json" |> File.read!() |> Jason.decode!()
  @crypto "test/fixtures/active_record_encryption.json" |> File.read!() |> Jason.decode!()
  @env Enum.find(@crypto["environments"], &(&1["name"] == "explicit keys"))["env"]
  @secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
  @now ~U[2026-10-04 12:00:00.000000Z]
  @id 75_711
  @email "a11f-concurrency@example.invalid"

  setup do
    for spec <- Redis.cache_child_specs(), do: start_supervised!(spec)
    {:ok, ciphertext} = Secret.encrypt(@secret, @env)

    unboxed(fn ->
      assert Repo.query!("SELECT id FROM users WHERE id=$1 OR email=$2", [@id, @email],
               log: false
             ).rows == []

      RailsUser.insert!(%{
        id: @id,
        email: @email,
        api_key: "synthetic fixture words",
        encrypted_password: @source["login"]["user"]["encrypted_password"],
        otp_secret: ciphertext,
        otp_required_for_login: true,
        otp_backup_codes: [@source["login"]["user"]["encrypted_password"]],
        subscription_source: 0,
        active_until: nil,
        failed_otp_attempts: 3,
        settings: %{}
      })
    end)

    jtis = for _ <- 1..2, do: Ecto.UUID.generate()

    on_exit(fn ->
      unboxed(fn ->
        Repo.query!("DELETE FROM users WHERE id=$1 AND email=$2", [@id, @email], log: false)
      end)

      config = Application.fetch_env!(:dawarich, :redis)
      {:ok, conn} = Redix.start_link(config[:url], database: config[:cache_database])
      for jti <- jtis, do: Redix.command(conn, ["DEL", "otp_challenge:consumed:" <> jti])
      GenServer.stop(conn)
    end)

    %{jtis: jtis}
  end

  test "API OTP stale consumers match source concurrent successes and final state", c do
    owner = self()

    for {kind, jti} <- Enum.zip([:totp, :backup], c.jtis) do
      unboxed(fn ->
        Repo.get!(Account, @id)
        |> Ecto.Changeset.change(
          consumed_timestep: nil,
          failed_otp_attempts: 3,
          otp_backup_codes: [@source["login"]["user"]["encrypted_password"]]
        )
        |> Repo.update!(log: false)
      end)

      command = fn args ->
        result = Redis.cache_command(args)
        if hd(args) == "SET", do: send(owner, {:mark, Process.get(:a11f_worker), result})
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
        cache_command: command
      }

      {:ok, token} = ChallengeToken.issue(@id, context)

      code =
        if kind == :totp, do: Totp.at(@secret, DateTime.to_unix(@now)), else: "safepassword12"

      workers =
        for index <- 0..1 do
          Task.async(fn ->
            unboxed(fn ->
              Process.put(:a11f_worker, index)
              [[backend]] = Repo.query!("SELECT pg_backend_pid()", [], log: false).rows
              assert {:ok, prepared} = Challenge.prepare(token, code, context)
              send(owner, {:prepared, self(), backend, prepared.user.consumed_timestep})

              receive do
                :commit -> ChallengeWrite.commit(prepared, context)
              after
                5000 -> raise "a11f prepared overlap timeout"
              end
            end)
          end)
        end

      try do
        assert_receive {:prepared, first, backend1, nil}, 5000
        assert_receive {:prepared, second, backend2, nil}, 5000
        assert backend1 != backend2

        observer =
          unboxed(fn ->
            Repo.query!("SELECT pg_backend_pid()", [], log: false).rows |> hd() |> hd()
          end)

        refute observer in [backend1, backend2]

        Enum.each(workers, fn task ->
          send(task.pid, :commit)
          assert {:ok, _} = Task.await(task, 5000)
        end)

        source = Enum.find(@races, &(&1["name"] == "#{kind}-prepared-overlap"))
        assert Enum.map(source["outcomes"], & &1["status"]) == [200, 200]
        assert_receive {:mark, 0, {:ok, "OK"}}
        assert_receive {:mark, 1, {:ok, nil}}
        assert source["marks"] == [[0, true], [1, false]]
        user = unboxed(fn -> Repo.get!(Account, @id) end)
        assert user.failed_otp_attempts == 0
        assert user.consumed_timestep == if(kind == :totp, do: div(DateTime.to_unix(@now), 30))

        assert user.otp_backup_codes ==
                 if(kind == :backup,
                   do: [],
                   else: [@source["login"]["user"]["encrypted_password"]]
                 )

        later = DateTime.add(@now, 30)

        assert {:replay, _} =
                 unboxed(fn ->
                   Challenge.prepare(token, Totp.at(@secret, DateTime.to_unix(later)), %{
                     context
                     | clock: fn -> later end
                   })
                 end)

        assert first != second
      after
        for worker <- workers, Process.alive?(worker.pid), do: Task.shutdown(worker, :brutal_kill)
      end
    end
  end

  defp unboxed(fun), do: Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fun)
end
