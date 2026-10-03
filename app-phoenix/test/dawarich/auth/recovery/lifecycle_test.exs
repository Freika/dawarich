defmodule Dawarich.Auth.Recovery.LifecycleTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.Recovery.{Lifecycle, Token}
  alias Dawarich.Repo
  @secret "phoenix-a2-cookie-fixture-secret-not-for-production"
  @now ~U[2026-10-01 12:00:00.000000Z]
  @source Jason.decode!(
            File.read!(Path.expand("../../../fixtures/auth/recovery/lifecycle.json", __DIR__))
          )
  @hash hd(@source["resets"])["before"]["encrypted_password"]

  defmodule NoTransactionRepo do
    def transaction(_fun), do: raise("a recovery transaction opened without a signing secret")
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    email = "recovery-#{System.unique_integer([:positive])}@dawarich.test"
    digest = Token.digest(:reset_password_token, "old-reset", @secret)

    [[id]] =
      Repo.query!(
        """
        INSERT INTO users(email,encrypted_password,reset_password_token,reset_password_sent_at,
          failed_attempts,locked_at,unlock_token,failed_otp_attempts,otp_locked_at,
          remember_created_at,created_at,updated_at)
        VALUES($1,$2,$3,$4,11,$4,'old-unlock',10,$4,$4,$4,$4) RETURNING id
        """,
        [email, @hash, digest, DateTime.add(@now, -60)]
      ).rows

    %{
      id: id,
      email: email,
      context: %{secret: @secret, clock: fn -> @now end, log_rounds: 4, self_hosted: true}
    }
  end

  test "issuance rotates reset token and preserves unrelated locks", c do
    before = Repo.get!(Account, c.id)

    assert {:ok, %{notification: notification}} =
             Lifecycle.request_reset(" #{String.upcase(c.email)} ", c.context)

    assert notification.kind == :reset_password_instructions
    after_row = Repo.get!(Account, c.id)

    assert after_row.reset_password_token ==
             Token.digest(:reset_password_token, notification.raw, @secret)

    assert after_row.reset_password_sent_at == @now
    assert after_row.failed_otp_attempts == before.failed_otp_attempts
    assert after_row.locked_at == before.locked_at
    assert {:error, :not_found} = Lifecycle.request_reset("unknown@dawarich.test", c.context)
  end

  test "successful reset consumes token, clears both lockouts and invalidates old salt", c do
    before = Repo.get!(Account, c.id)
    assert {:ok, user} = Lifecycle.reset("old-reset", "newpassword12345", nil, c.context)
    assert Bcrypt.verify_pass("newpassword12345", user.encrypted_password)
    assert user.reset_password_token == nil
    assert user.reset_password_sent_at == nil
    assert user.failed_otp_attempts == 0
    assert user.otp_locked_at == nil
    assert user.failed_attempts == 0
    assert user.locked_at == nil
    assert user.unlock_token == nil
    assert user.remember_created_at == before.remember_created_at
    assert user.sign_in_count == before.sign_in_count

    refute Dawarich.Accounts.from_session(
             %{"warden.user.user.key" => [[c.id], String.slice(@hash, 0, 29)]},
             @now
           )

    assert {:error, :invalid} =
             Lifecycle.reset("old-reset", "anotherpassword12", "anotherpassword12", c.context)
  end

  test "a token sent exactly six hours ago is still accepted", c do
    Repo.query!("UPDATE users SET reset_password_sent_at=$1 WHERE id=$2", [
      DateTime.add(@now, -21_600),
      c.id
    ])

    assert {:ok, _} =
             Lifecycle.reset("old-reset", "newpassword12345", "newpassword12345", c.context)
  end

  test "expiry and validation errors do not mutate recovery fields", c do
    Repo.query!("UPDATE users SET reset_password_sent_at=$1 WHERE id=$2", [
      DateTime.add(@now, -21_600_000_001, :microsecond),
      c.id
    ])

    before = Repo.get!(Account, c.id)

    assert {:error, :expired} =
             Lifecycle.reset("old-reset", "newpassword12345", "newpassword12345", c.context)

    assert Repo.get!(Account, c.id) == before
    Repo.query!("UPDATE users SET reset_password_sent_at=$1 WHERE id=$2", [@now, c.id])
    before = Repo.get!(Account, c.id)

    assert {:error, {:validation, [:too_short]}} =
             Lifecycle.reset("old-reset", "short", "short", c.context)

    assert {:error, {:validation, [:confirmation]}} =
             Lifecycle.reset("old-reset", "newpassword12345", "different", c.context)

    assert {:error, {:validation, [:confirmation, :too_short]}} =
             Lifecycle.reset("old-reset", "short", "different", c.context)

    assert Repo.get!(Account, c.id) == before
  end

  test "unlock resend rotates token; consumption and replay are single use", c do
    assert {:ok, %{notification: first}} = Lifecycle.request_unlock(c.email, c.context)
    assert {:ok, %{notification: second}} = Lifecycle.request_unlock(c.email, c.context)
    refute first.raw == second.raw
    assert {:error, :invalid} = Lifecycle.unlock(first.raw, c.context)
    assert {:ok, user} = Lifecycle.unlock(second.raw, c.context)
    assert user.locked_at == nil and user.unlock_token == nil and user.failed_attempts == 0
    assert user.failed_otp_attempts == 10
    assert {:error, :invalid} = Lifecycle.unlock(second.raw, c.context)
    assert {:error, :not_locked} = Lifecycle.request_unlock(c.email, c.context)
  end

  test "nil issuance time rejects while future time follows actual Rails acceptance", c do
    Repo.query!("UPDATE users SET reset_password_sent_at=NULL WHERE id=$1", [c.id])
    assert {:error, :expired} = Lifecycle.reset("old-reset", "newpassword12345", nil, c.context)

    Repo.query!("UPDATE users SET reset_password_sent_at=$1 WHERE id=$2", [
      DateTime.add(@now, 60),
      c.id
    ])

    assert {:ok, _} = Lifecycle.reset("old-reset", "newpassword12345", nil, c.context)
  end

  test "actual Ruby bcrypt accepts 100 codepoints and truncates only hashing bytes", c do
    password = String.duplicate("a", 100)
    assert {:ok, user} = Lifecycle.reset("old-reset", password, password, c.context)
    assert Bcrypt.verify_pass(String.duplicate("a", 72), user.encrypted_password)
  end

  test "Rails verifies the bcrypt variant Phoenix writes on reset", c do
    rows = @source["phoenix_hashes"]
    assert length(rows) == 3

    for %{"password" => password, "hash" => hash} = row <- rows do
      assert row["rails_valid_password"]
      assert Bcrypt.verify_pass(binary_part(password, 0, min(byte_size(password), 72)), hash)
    end

    assert {:ok, user} = Lifecycle.reset("old-reset", "newpassword12345", nil, c.context)
    assert binary_part(user.encrypted_password, 0, 4) == binary_part(hd(rows)["hash"], 0, 4)
  end

  test "Ruby codepoint length counts combining marks independently", c do
    password = String.duplicate("a\u0301", 6)
    assert String.length(password) == 6
    assert {:ok, _} = Lifecycle.reset("old-reset", password, password, c.context)
  end

  test "paranoid requests apply Rails' save-callback settings in the issuing write and hand back only where Rails raises",
       c do
    for row <- @source["sanitized_requests"] do
      Repo.query!(
        "UPDATE users SET settings=$1,locked_at=$2,failed_attempts=$3,reset_password_token=NULL,unlock_token=NULL WHERE id=$4",
        [
          row["settings_before"],
          if(row["locked"], do: @now),
          if(row["locked"], do: 10, else: 0),
          c.id
        ]
      )

      result =
        if row["kind"] == "reset",
          do: Lifecycle.request_reset(c.email, c.context),
          else: Lifecycle.request_unlock(c.email, c.context)

      cond do
        row["raised"] -> assert result == {:handoff, :settings_callback}, row["name"]
        row["notified"] == [] -> assert result == {:error, :not_locked}, row["name"]
        true -> assert {:ok, %{notification: %{kind: _}}} = result, row["name"]
      end

      [[settings, reset, unlock]] =
        Repo.query!(
          "SELECT settings,reset_password_token,unlock_token FROM users WHERE id=$1",
          [c.id]
        ).rows

      assert settings == row["settings_after"], row["name"]
      assert is_binary(if(row["kind"] == "reset", do: reset, else: unlock)) == row["token_issued"]
    end
  end

  test "token redemption for an account whose settings Rails' save callback rewrites hands back before any effect",
       c do
    Repo.query!("UPDATE users SET settings=$1,unlock_token=$2 WHERE id=$3", [
      %{"immich_url" => "https://synthetic.test/"},
      Token.digest(:unlock_token, "unsafe-unlock", @secret),
      c.id
    ])

    before = Repo.get!(Account, c.id)

    assert {:handoff, :settings_callback} =
             Lifecycle.reset("old-reset", "newpassword12345", nil, c.context)

    assert {:handoff, :settings_callback} = Lifecycle.unlock("unsafe-unlock", c.context)
    assert Repo.get!(Account, c.id) == before
  end

  test "a pending-payment account hands back after its valid token, before any write, for Rails' trial resume",
       c do
    Repo.query!("UPDATE users SET status=3 WHERE id=$1", [c.id])
    before = Repo.get!(Account, c.id)

    assert Lifecycle.reset("old-reset", "newpassword12345", nil, c.context) ==
             {:handoff, :payment}

    assert Repo.get!(Account, c.id) == before
  end

  test "a reset outside self-hosting hands back for Rails' password-change notification", c do
    before = Repo.get!(Account, c.id)

    for context <- [Map.put(c.context, :self_hosted, false), Map.delete(c.context, :self_hosted)] do
      assert Lifecycle.reset("old-reset", "newpassword12345", nil, context) ==
               {:handoff, :password_change_notification}
    end

    assert Repo.get!(Account, c.id) == before
  end

  test "a missing signing secret hands back before any recovery transaction", c do
    context = %{c.context | secret: nil} |> Map.put(:repo, NoTransactionRepo)
    assert Lifecycle.request_reset(c.email, context) == {:handoff, :secret}
    assert Lifecycle.request_unlock(c.email, context) == {:handoff, :secret}
    assert Lifecycle.reset("old-reset", "newpassword12345", nil, context) == {:handoff, :secret}
    assert Lifecycle.unlock("old-unlock", context) == {:handoff, :secret}
  end

  test "Devise token generation retries a digest already present on a live account", c do
    {:ok, agent} = Agent.start_link(fn -> ["old-reset", "fresh-synthetic"] end)
    generator = fn -> Agent.get_and_update(agent, fn [raw | rest] -> {raw, rest} end) end

    assert {:ok, %{notification: notification}} =
             Lifecycle.request_reset(c.email, Map.put(c.context, :token_generator, generator))

    assert notification.raw == "fresh-synthetic"
    Agent.stop(agent)
  end

  test "blank reset tokens report the actual distinct Rails blank error", c do
    assert {:error, :blank_token} = Lifecycle.reset("", "newpassword12345", nil, c.context)
    assert {:error, :blank_token} = Lifecycle.reset(nil, "newpassword12345", nil, c.context)
  end

  test "actual Ruby Unicode cases include a bcrypt truncation inside a UTF-8 sequence", c do
    for row <- Enum.take(@source["resets"], -2) do
      assert row["errors"] == %{} and row["valid_password"]

      assert Bcrypt.verify_pass(
               row["password"],
               row["controller_unlock_after"]["encrypted_password"]
             )

      Repo.query!(
        "UPDATE users SET reset_password_token=$1,reset_password_sent_at=$2 WHERE id=$3",
        [Token.digest(:reset_password_token, "unicode-reset", @secret), @now, c.id]
      )

      assert {:ok, user} =
               Lifecycle.reset("unicode-reset", row["password"], row["confirmation"], c.context)

      assert Bcrypt.verify_pass(row["password"], user.encrypted_password)
    end
  end
end
