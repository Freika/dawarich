defmodule Dawarich.Auth.Api.LoginTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.{Account, Api.Login}
  alias Dawarich.Auth.TwoFactor.Secret
  alias Dawarich.{Repo, Test.RailsUser}

  @source "test/fixtures/auth/requests.json" |> File.read!() |> Jason.decode!()
  @crypto "test/fixtures/active_record_encryption.json" |> File.read!() |> Jason.decode!()
  @env Enum.find(@crypto["environments"], &(&1["name"] == "explicit keys"))["env"]
  @id 75_610
  @context %{self_hosted: true, oidc: false, timezone: "Etc/UTC", env: @env}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    RailsUser.insert!(%{
      id: @id,
      email: "a11f-login@example.invalid",
      api_key: "synthetic fixture words",
      encrypted_password: @source["login"]["user"]["encrypted_password"],
      subscription_source: 0,
      active_until: nil,
      settings: %{}
    })

    :ok
  end

  test "API password selection normalizes source email and never mutates login state" do
    for status <- 0..3, locked <- [nil, ~U[2026-10-04 12:00:00.000000Z]] do
      seed(%{status: status, locked_at: locked, failed_attempts: 7})
      before = snapshot()

      assert {:success, user, {:object, pairs}} =
               Login.prepare("  A11F-LOGIN@EXAMPLE.INVALID  ", "safepassword12", @context)

      assert user.id == @id and Map.new(pairs)["user_id"] == @id
      assert snapshot() == before
    end

    for {password, supplied} <- [
          {String.duplicate("a", 72) <> "x", String.duplicate("a", 72) <> "y"},
          {"pässwörd-旅行-123456", "pässwörd-旅行-123456"}
        ] do
      seed(%{encrypted_password: Bcrypt.hash_pwd_salt(password, log_rounds: 4)})
      before = snapshot()
      assert {:success, _, _} = Login.prepare("a11f-login@example.invalid", supplied, @context)
      assert snapshot() == before
    end

    seed(%{encrypted_password: @source["login"]["user"]["encrypted_password"]})

    for {email, password} <- [
          {"a11f-login@example.invalid", "wrong"},
          {"missing@example.invalid", "safepassword12"},
          {" ", "safepassword12"},
          {nil, "safepassword12"},
          {"a11f-login@example.invalid", ""},
          {"a11f-login@example.invalid", nil},
          {[], "safepassword12"},
          {"a11f-login@example.invalid", <<0>>}
        ] do
      before = snapshot()
      assert {:replay, _} = Login.prepare(email, password, @context)
      assert snapshot() == before
    end

    {:ok, ciphertext} = Secret.encrypt("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", @env)
    seed(%{otp_required_for_login: true, otp_secret: ciphertext})
    before = snapshot()

    assert {:challenge, user} =
             Login.prepare("a11f-login@example.invalid", "safepassword12", @context)

    assert user.id == @id
    assert {:replay, _} = Login.prepare(user.email, "safepassword12", %{@context | env: %{}})
    assert snapshot() == before
    seed(%{otp_required_for_login: false})
    assert {:success, _, _} = Login.prepare(user.email, "safepassword12", %{@context | env: %{}})
    seed(%{otp_required_for_login: true, otp_secret: "unreadable"})
    assert {:replay, _} = Login.prepare(user.email, "safepassword12", @context)
    seed(%{otp_required_for_login: false, provider: "openid_connect"})
    assert {:replay, _} = Login.prepare(user.email, "safepassword12", @context)
    seed(%{provider: nil, deleted_at: ~U[2026-10-04 12:00:00.000000Z]})
    assert {:replay, _} = Login.prepare(user.email, "safepassword12", @context)
  end

  test "API password preflight doubles the Rails work pattern for the same actor or miss" do
    path =
      Path.join(
        System.tmp_dir!(),
        "a11f-password-work-#{System.unique_integer([:positive])}.json"
      )

    for context <- [@context, Map.put(@context, :log_rounds, 6)] do
      try do
        Dawarich.Auth.ApiProtocol.password_work(path, context)
        payload = path |> File.read!() |> Jason.decode!()
        cost = payload["dummy_cost"]
        if context[:log_rounds], do: assert(cost == context.log_rounds)

        hash_names =
          for minor <- ~w(2a 2b 2x 2y),
              cost <- ~w(00 01 02 03 32 99),
              do: "uncomputable-#{minor}-#{cost}"

        assert Enum.map(payload["rows"], & &1["name"]) ==
                 ~w(known-wrong known-wrong-low-cost known-wrong-2a-low-cost rejected-2a-low-cost rejected-2y-low-cost rejected-2x-low-cost wrong-nul-known wrong-nul-unknown wrong-nul-deleted correct-nul correct-nul-otp wrong-nul-form correct-nul-form unicode-known unicode-unknown unicode-deleted unknown deleted blank-hash provider provider-low-cost settings settings-low-cost metadata metadata-low-cost validation validation-low-cost) ++
                   hash_names ++ ~w(uncomputable-2z uncomputable-1a invalid-hash)

        for row <- payload["rows"] do
          if String.contains?(row["name"], "nul") or String.starts_with?(row["name"], "unicode") do
            assert row["native_work"] == [], row["name"]
            assert row["native_lookups"] == 0, row["name"]
          else
            assert row["native_lookups"] == 1, row["name"]

            expected =
              case row["name"] do
                "blank-hash" ->
                  [cost, cost]

                "invalid-hash" ->
                  []

                "uncomputable-" <> _ ->
                  [cost, cost]

                name when name in ["unknown", "deleted"] ->
                  [cost]

                _ ->
                  [
                    row["state"]["encrypted_password"]
                    |> String.split("$")
                    |> Enum.at(2)
                    |> String.to_integer()
                  ]
              end

            rails_work =
              if row["name"] == "blank-hash" or String.starts_with?(row["name"], "uncomputable"),
                do: [],
                else: expected

            baseline =
              if rails_work == [] and row["name"] != "invalid-hash", do: [cost], else: rails_work

            assert row["native_work"] ++ rails_work == baseline ++ baseline, row["name"]
          end
        end
      after
        if File.exists?(path), do: File.rm!(path)
      end
    end
  end

  test "API non-ASCII emails replay before actor selection or password work" do
    upper = <<0xE1, 0xB2, 0x89>> <> "@example.invalid"
    lower = <<0xE1, 0xB2, 0x8A>> <> "@example.invalid"

    for stored <- [upper, lower, "päss@example.invalid"] do
      seed(%{email: stored})
      before = snapshot()

      for submitted <- [upper, lower, stored], password <- ["safepassword12", "wrong"] do
        result = Login.prepare(submitted, password, @context)
        assert match?({:replay, _}, result), "non-ASCII actor selection must replay"

        assert snapshot() == before
      end
    end
  end

  defp snapshot,
    do: Repo.query!("SELECT to_jsonb(u) FROM users u ORDER BY id", [], log: false).rows

  defp seed(changes),
    do: Repo.get!(Account, @id) |> Ecto.Changeset.change(changes) |> Repo.update!(log: false)
end
