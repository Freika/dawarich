defmodule Dawarich.Auth.Api.ChallengeTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.{Account, Api.Challenge}
  alias Dawarich.Auth.TwoFactor.{Secret, Totp}
  alias Dawarich.{Redis, Repo, Test.RailsUser}
  alias Dawarich.Test.ApiJwtFixture
  @source "test/fixtures/auth/requests.json" |> File.read!() |> Jason.decode!()
  @crypto "test/fixtures/active_record_encryption.json" |> File.read!() |> Jason.decode!()
  @env Enum.find(@crypto["environments"], &(&1["name"] == "explicit keys"))["env"]
  @secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
  @now ApiJwtFixture.now()
  @id ApiJwtFixture.user_id()

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    for spec <- Redis.cache_child_specs(), do: start_supervised!(spec)

    row =
      ApiJwtFixture.vectors()
      |> Enum.find(&(&1["name"] == "explicit"))

    {:ok, ciphertext} = Secret.encrypt(@secret, @env)

    RailsUser.insert!(%{
      id: @id,
      email: "a11f-challenge@example.invalid",
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

    %{
      token: row["token"],
      context: %{
        self_hosted: true,
        oidc: false,
        timezone: "Etc/UTC",
        env: Map.put(@env, "JWT_SECRET_KEY", ApiJwtFixture.secret("jwt")),
        clock: fn -> @now end
      },
      key: "otp_challenge:consumed:" <> row["jti"]
    }
  end

  test "API challenge selects source TOTP then backup and replays refusals before effects", c do
    code = Totp.at(@secret, DateTime.to_unix(@now))

    for {input, timestep} <- [
          {code, div(DateTime.to_unix(@now), 30)},
          {"  " <> code <> "  ", div(DateTime.to_unix(@now), 30)},
          {String.slice(code, 0, 3) <> " " <> String.slice(code, 3, 3),
           div(DateTime.to_unix(@now), 30)},
          {Totp.at(@secret, DateTime.to_unix(@now) - 30), div(DateTime.to_unix(@now), 30) - 1},
          {Totp.at(@secret, DateTime.to_unix(@now) + 30), div(DateTime.to_unix(@now), 30) + 1}
        ] do
      before = snapshot()
      assert {:ok, prepared} = Challenge.prepare(c.token, input, c.context)
      assert prepared.kind == :totp and prepared.changes == %{consumed_timestep: timestep}
      assert prepared.user.id == @id
      assert snapshot() == before
      assert {:ok, nil} = Redis.cache_command(["GET", c.key])
    end

    seed(%{otp_backup_codes: [Bcrypt.hash_pwd_salt(code, log_rounds: 4)]})
    assert {:ok, %{kind: :totp}} = Challenge.prepare(c.token, code, c.context)
    seed(%{otp_backup_codes: [@source["login"]["user"]["encrypted_password"]]})

    for locked <- [nil, DateTime.add(@now, -60)] do
      seed(%{otp_locked_at: locked})
      before = snapshot()
      assert {:ok, prepared} = Challenge.prepare(c.token, "  safepassword12  ", c.context)
      assert prepared.kind == :backup and prepared.changes == %{otp_backup_codes: []}
      assert snapshot() == before
    end

    assert {:replay, _} = Challenge.prepare(c.token, code, c.context)

    seed(%{
      otp_locked_at: nil,
      consumed_timestep: div(DateTime.to_unix(@now), 30),
      otp_backup_codes: []
    })

    for input <- [
          code,
          "safepassword12",
          "invalid",
          nil,
          [],
          <<0>>,
          Totp.at(@secret, DateTime.to_unix(@now) - 60)
        ] do
      before = snapshot()
      assert {:replay, _} = Challenge.prepare(c.token, input, c.context)
      assert snapshot() == before
      assert {:ok, nil} = Redis.cache_command(["GET", c.key])
    end

    seed(%{consumed_timestep: nil})

    for changes <- [
          %{otp_required_for_login: false},
          %{otp_secret: nil},
          %{otp_secret: "unreadable"},
          %{deleted_at: @now}
        ] do
      original = Repo.get!(Account, @id)
      seed(changes)
      before = snapshot()
      assert {:replay, _} = Challenge.prepare(c.token, code, c.context)
      assert snapshot() == before
      seed(Map.take(Map.from_struct(original), Map.keys(changes)))
    end

    assert {:replay, _} = Challenge.prepare(c.token, code, %{c.context | env: %{}})
    assert {:replay, _} = Challenge.prepare("malformed", code, c.context)
    context = Map.put(c.context, :cache_command, fn _ -> {:ok, "unsupported"} end)

    assert {:replay, _} =
             Challenge.prepare(c.token, code, Map.put(context, :repo, :must_not_load_actor))

    leading =
      Enum.find_value(1..1000, fn n ->
        secret = Totp.generate_secret("a11f-leading-#{n}")
        if String.starts_with?(Totp.at(secret, DateTime.to_unix(@now)), "0"), do: secret
      end)

    {:ok, ciphertext} = Secret.encrypt(leading, @env)
    seed(%{otp_secret: ciphertext})

    assert {:ok, %{kind: :totp}} =
             Challenge.prepare(c.token, Totp.at(leading, DateTime.to_unix(@now)), c.context)
  end

  test "API challenge NUL tokens and codes replay before lookup or consumption", c do
    before = snapshot()

    context =
      c.context
      |> Map.put(:repo, :must_not_load_actor)
      |> Map.put(:cache_command, fn _ -> raise "NUL challenge reached cache" end)

    for {token, code} <- [
          {c.token, "wrong" <> <<0>> <> "suffix"},
          {c.token, "safepassword12" <> <<0>> <> "suffix"},
          {c.token <> <<0>> <> "suffix", "safepassword12"}
        ] do
      assert {:replay, _} = Challenge.prepare(token, code, context)
      assert snapshot() == before
      assert {:ok, nil} = Redis.cache_command(["GET", c.key])
    end
  end

  test "API OTP refusal preflight mirrors read-only Rails verification before replay", c do
    path =
      Path.join(System.tmp_dir!(), "a11f-otp-work-#{System.unique_integer([:positive])}.json")

    try do
      Dawarich.Auth.ApiProtocol.otp_work(path, c.context)
      payload = path |> File.read!() |> Jason.decode!()

      assert Enum.map(payload["rows"], & &1["name"]) ==
               ~w(supported-wrong provider-wrong legacy-wrong nil-secret blank-secret unreadable-secret invalid-secret disabled locked-provider locked-unreadable provider-totp provider-backup legacy-backup nil-secret-backup settings missing-encryption-setting uncomputable-backup-00 uncomputable-backup-01 uncomputable-backup-02 uncomputable-backup-03 nil-backup invalid-backup password-state)

      for row <- payload["rows"] do
        assert row["native_work"] == row["expected_work"], row["name"]
      end
    after
      if File.exists?(path), do: File.rm!(path)
    end
  end

  test "API challenge IDs outside bigint replay before cache or actor lookup", c do
    alias Dawarich.Auth.Api.ChallengeToken

    context =
      Map.put(c.context, :cache_command, fn _ -> raise "out-of-range challenge reached cache" end)

    for id <- [9_223_372_036_854_775_808, 18_446_744_073_709_551_616] do
      {:ok, token} = ChallengeToken.issue(id, c.context)
      assert match?({:replay, _}, Challenge.prepare(token, "wrong", context))
    end

    {:ok, token} = ChallengeToken.issue(9_223_372_036_854_775_807, c.context)
    assert match?({:ok, _}, ChallengeToken.verify(token, c.context))
  end

  defp snapshot,
    do: Repo.query!("SELECT to_jsonb(u) FROM users u ORDER BY id", [], log: false).rows

  defp seed(changes),
    do: Repo.get!(Account, @id) |> Ecto.Changeset.change(changes) |> Repo.update!(log: false)
end
