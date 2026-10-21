defmodule Dawarich.Auth.Otp.CompletionTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.{Account, Otp.Completion}
  alias Dawarich.Auth.TwoFactor.{Secret, Totp}
  alias Dawarich.{Repo, Test.RailsUser}

  @source "test/fixtures/auth/requests.json" |> File.read!() |> Jason.decode!()
  @crypto "test/fixtures/active_record_encryption.json" |> File.read!() |> Jason.decode!()
  @env Enum.find(@crypto["environments"], &(&1["name"] == "explicit keys"))["env"]
  @vectors "test/fixtures/auth/two_factor/otp.json" |> File.read!() |> Jason.decode!()
  @secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
  @now ~U[2026-10-04 12:00:00.000000Z]
  @id 75_510

  defmodule OrderedRepo do
    defdelegate one(query, opts), to: Repo
    defdelegate query!(query, params, opts), to: Repo
    defdelegate transaction(fun), to: Repo

    def update!(changeset, opts) do
      kind =
        cond do
          Map.has_key?(changeset.changes, :consumed_timestep) -> :consume
          Map.has_key?(changeset.changes, :otp_backup_codes) -> :consume
          Map.has_key?(changeset.changes, :failed_otp_attempts) -> :reset
          Map.has_key?(changeset.changes, :remember_created_at) -> :remember
          Map.has_key?(changeset.changes, :failed_attempts) -> :devise
          Map.has_key?(changeset.changes, :sign_in_count) -> :trackable
        end

      if Process.get(:a11d_fail_at) == kind, do: raise("a11d-#{kind}-failure")
      user = Repo.update!(changeset, opts)
      send(self(), {:otp_write, kind})
      user
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    {:ok, ciphertext} = Secret.encrypt(@secret, @env)

    RailsUser.insert!(%{
      id: @id,
      email: "a11d-completion@dawarich.test",
      encrypted_password: @source["login"]["user"]["encrypted_password"],
      otp_secret: ciphertext,
      otp_required_for_login: true,
      otp_backup_codes: [@source["login"]["user"]["encrypted_password"]],
      failed_attempts: 2,
      failed_otp_attempts: 3,
      sign_in_count: 7,
      api_key: "synthetic fixture words",
      settings: %{}
    })

    %{
      context: %{
        self_hosted: true,
        oidc: false,
        env: @env,
        clock: fn -> @now end,
        ip: "127.0.0.1"
      },
      session: %{
        "otp_user_id" => @id,
        "otp_challenge_at" => DateTime.to_unix(@now),
        "otp_remember_me" => true,
        "otp_failed_attempts" => 2,
        "locale" => "en"
      }
    }
  end

  defp snapshot do
    Repo.query!("SELECT to_jsonb(u) FROM users u ORDER BY id", [], log: false).rows
  end

  defp seed(values),
    do: Repo.get!(Account, @id) |> Ecto.Changeset.change(values) |> Repo.update!(log: false)

  test "web OTP consumption matches source sequential replay and overlapping stale reads", c do
    for {kind, code} <- [totp: Totp.at(@secret, DateTime.to_unix(@now)), backup: "safepassword12"] do
      seed(
        consumed_timestep: nil,
        otp_backup_codes: [@source["login"]["user"]["encrypted_password"]]
      )

      assert {:ok, first} = Completion.prepare(c.session, code, c.context)
      assert {:ok, second} = Completion.prepare(c.session, code, c.context)
      assert first.kind == kind and second.kind == kind
      assert {:ok, _} = Completion.commit(first, c.context)
      assert match?({:handoff, _}, Completion.prepare(c.session, code, c.context))
      assert {:ok, _} = Completion.commit(second, c.context)
      assert match?({:handoff, _}, Completion.prepare(c.session, code, c.context))
      user = Repo.get!(Account, @id)
      if kind == :totp, do: assert(user.consumed_timestep == div(DateTime.to_unix(@now), 30))
      if kind == :backup, do: assert(user.otp_backup_codes == [])
      assert user.sign_in_count == first.user.sign_in_count + 1
    end
  end

  test "successful completion commits consumption before OTP reset and source sign-in deltas",
       c do
    Code.ensure_loaded!(Completion)
    assert function_exported?(Completion, :commit, 2)
    context = Map.put(c.context, :repo, OrderedRepo)
    source = File.read!("test/fixtures/auth/otp/requests.json") |> Jason.decode!()

    RailsUser.insert!(%{
      id: @id + 1,
      email: "a11d-unrelated@dawarich.test",
      api_key: "A11D_UNRELATED",
      settings: %{}
    })

    before_all = snapshot()
    stamp = DateTime.add(@now, -86_400)

    for name <- ~w(totp totp_remember backup backup_locked) do
      seed(
        consumed_timestep: nil,
        failed_attempts: 2,
        failed_otp_attempts: 3,
        sign_in_count: 0,
        current_sign_in_at: nil,
        last_sign_in_at: nil,
        current_sign_in_ip: nil,
        last_sign_in_ip: nil,
        remember_created_at: nil,
        unlock_token: "synthetic-unlock",
        otp_locked_at: if(name == "backup_locked", do: DateTime.add(@now, -60)),
        otp_backup_codes: [@source["login"]["user"]["encrypted_password"]]
      )

      session = Map.put(c.session, "otp_remember_me", name == "totp_remember")

      [[unchanged_before]] =
        Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [@id], log: false).rows

      code =
        if String.starts_with?(name, "backup"),
          do: "safepassword12",
          else: Totp.at(@secret, DateTime.to_unix(@now))

      assert {:ok, prepared} = Completion.prepare(session, code, context)
      assert {:ok, result} = Completion.commit(prepared, context)
      user = Repo.get!(Account, @id)
      row = source[name]["state"]

      for field <-
            ~w(consumed_timestep failed_attempts failed_otp_attempts sign_in_count current_sign_in_ip last_sign_in_ip) do
        assert Map.fetch!(user, String.to_existing_atom(field)) == row[field],
               name <> ":" <> field
      end

      assert user.current_sign_in_at == @now and user.last_sign_in_at == @now
      assert user.updated_at == @now and user.otp_locked_at == nil
      assert user.unlock_token == "synthetic-unlock" and user.locked_at == nil
      assert length(user.otp_backup_codes) == row["backup_count"]
      assert result.session == %{"locale" => "en"}

      [[unchanged_after]] =
        Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [@id], log: false).rows

      changed_fields =
        ~w(consumed_timestep otp_backup_codes failed_attempts failed_otp_attempts otp_locked_at sign_in_count
                          current_sign_in_at last_sign_in_at current_sign_in_ip last_sign_in_ip remember_created_at updated_at)

      retained =
        Map.drop(unchanged_before, changed_fields) == Map.drop(unchanged_after, changed_fields)

      assert retained

      if name == "totp_remember" do
        assert user.remember_created_at == @now

        assert result.remember == [
                 [@id],
                 binary_part(user.encrypted_password, 0, 29),
                 Dawarich.Accounts.remember_generated_at(@now)
               ]
      else
        assert result.remember == nil
      end

      kinds = %{
        "consume_totp" => :consume,
        "consume_backup" => :consume,
        "reset_otp" => :reset,
        "remember" => :remember,
        "reset_devise" => :devise,
        "trackable" => :trackable
      }

      expected = Enum.map(source[name]["writes"], &Map.fetch!(kinds, &1))

      assert ordered_writes() == expected
    end

    for remember <- [true, false] do
      seed(consumed_timestep: nil, remember_created_at: stamp)
      session = Map.put(c.session, "otp_remember_me", remember)

      assert {:ok, prepared} =
               Completion.prepare(session, Totp.at(@secret, DateTime.to_unix(@now)), c.context)

      assert {:ok, _} = Completion.commit(prepared, c.context)
      assert Repo.get!(Account, @id).remember_created_at == stamp
    end

    for failure <- [:reset, :trackable] do
      seed(consumed_timestep: nil, failed_otp_attempts: 3, otp_locked_at: nil)

      assert {:ok, prepared} =
               Completion.prepare(c.session, Totp.at(@secret, DateTime.to_unix(@now)), context)

      Process.put(:a11d_fail_at, failure)

      try do
        assert_raise RuntimeError, "a11d-#{failure}-failure", fn ->
          Completion.commit(prepared, context)
        end
      after
        Process.delete(:a11d_fail_at)
      end

      user = Repo.get!(Account, @id)
      assert user.consumed_timestep == div(DateTime.to_unix(@now), 30)
      assert user.failed_otp_attempts == if(failure == :reset, do: 3, else: 0)
    end

    after_all = snapshot()

    unchanged_actors =
      Enum.reject(after_all, fn [row] -> row["id"] == @id end) ==
        Enum.reject(before_all, fn [row] -> row["id"] == @id end)

    assert unchanged_actors
  end

  defp ordered_writes do
    receive do
      {:otp_write, kind} -> [kind | ordered_writes()]
    after
      0 -> []
    end
  end

  test "completion selects TOTP before backup and sends every refusal to Rails without effects",
       c do
    assert Code.ensure_loaded?(Completion)

    for row <- @vectors["vectors"] do
      seed(consumed_timestep: row["consumed"])
      before = snapshot()
      now = DateTime.from_unix!(row["at"])
      context = %{c.context | clock: fn -> now end}
      session = Map.put(c.session, "otp_challenge_at", row["at"])
      result = Completion.prepare(session, row["code"], context)

      if row["valid"] do
        assert {:ok, prepared} = result
        assert prepared.kind == :totp
        assert prepared.changes == %{consumed_timestep: row["result_timestep"]}
        assert prepared.remember == true
        assert prepared.session == %{"locale" => "en"}
      else
        assert match?({:handoff, _}, result), row["name"]
      end

      unchanged = snapshot() == before
      assert unchanged, row["name"]
    end

    code = Totp.at(@secret, DateTime.to_unix(@now))
    duplicate = Bcrypt.hash_pwd_salt(code, log_rounds: 4)
    seed(consumed_timestep: nil, otp_backup_codes: [duplicate])
    before = snapshot()
    assert {:ok, prepared} = Completion.prepare(c.session, code, c.context)
    assert prepared.kind == :totp
    assert snapshot() == before

    seed(
      otp_locked_at: DateTime.add(@now, -60),
      otp_backup_codes: [@source["login"]["user"]["encrypted_password"]]
    )

    before = snapshot()
    result = Completion.prepare(c.session, code, c.context)
    assert match?({:handoff, _}, result)
    assert {:ok, prepared} = Completion.prepare(c.session, "safepassword12", c.context)
    assert prepared.kind == :backup and prepared.changes == %{otp_backup_codes: []}
    assert snapshot() == before
    seed(otp_locked_at: DateTime.add(@now, -1800))
    assert {:ok, %{kind: :totp}} = Completion.prepare(c.session, code, c.context)

    seed(
      otp_locked_at: nil,
      consumed_timestep: DateTime.to_unix(@now) |> div(30),
      otp_backup_codes: []
    )

    before = snapshot()

    for input <- [code, "safepassword12", "not-a-code", nil, []] do
      assert match?({:handoff, _}, Completion.prepare(c.session, input, c.context))
      assert snapshot() == before
    end

    for session <- [
          %{},
          Map.put(c.session, "otp_challenge_at", DateTime.to_unix(@now) - 300),
          Map.put(c.session, "otp_user_id", 99_999_999)
        ] do
      assert {:expired, cleared} = Completion.prepare(session, code, c.context)
      assert Map.keys(cleared) -- ["locale"] == []
      assert snapshot() == before
    end

    malformed = Map.put(c.session, "otp_challenge_at", "1791115200")
    assert Completion.prepare(malformed, code, c.context) == {:handoff, :pending}
    seed(otp_required_for_login: false)
    before = snapshot()
    assert match?({:handoff, _}, Completion.prepare(c.session, code, c.context))
    assert snapshot() == before
  end
end
