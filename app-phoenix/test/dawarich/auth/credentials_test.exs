defmodule Dawarich.Auth.CredentialsTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Auth.Credentials

  @fixture Jason.decode!(File.read!(Path.expand("../../fixtures/auth/requests.json", __DIR__)))
  @password_hash @fixture["user_before"]["encrypted_password"]
  @now ~U[2026-10-01 16:00:00.000000Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    email = "native-a11-#{System.unique_integer([:positive])}@dawarich.test"

    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO users(email,encrypted_password,status,created_at,updated_at) VALUES($1,$2,1,$3,$3) RETURNING id",
        [email, @password_hash, @now]
      )

    clock = start_supervised!({Agent, fn -> @now end})

    tick = fn ->
      Agent.get_and_update(clock, fn now -> {now, DateTime.add(now, 1000, :microsecond)} end)
    end

    %{id: id, email: email, context: %{repo: Repo, clock: tick, ip: "192.0.2.10"}}
  end

  test "normalizes email, verifies the actual Rails hash and issues a accepted remember credential",
       ctx do
    context = Map.put(ctx.context, :remember, true)

    assert {:ok, result} =
             Credentials.login("  #{String.upcase(ctx.email)}  ", "safepassword12", context)

    assert result.user.id == ctx.id
    assert result.user.failed_attempts == 0
    assert result.user.sign_in_count == 1
    assert result.user.current_sign_in_ip == "192.0.2.10"

    assert %Accounts.User{id: id} =
             Accounts.from_remember_cookie(result.remember, DateTime.add(@now, 10))

    assert id == ctx.id
  end

  test "verifies Ruby bcrypt hashes for 128 codepoint multibyte passwords using 72 bytes", ctx do
    for {character, hash} <- [
          {"ä", "$2a$04$PhoenixA12eCorpusSaltu1gB/351kOA0HkAFa22kBqCw.Bj8/Nyu"},
          {"😀", "$2a$04$PhoenixA12eCorpusSaltue6ptoJykW99b9t2pZDbOTzGTAIqXuHu"}
        ] do
      password = String.duplicate(character, 128)
      Repo.query!("UPDATE users SET encrypted_password=$1 WHERE id=$2", [hash, ctx.id])

      assert {:ok, result} = Credentials.login(ctx.email, password, ctx.context)
      assert result.user.id == ctx.id
      assert {:ok, _} = Credentials.login(ctx.email, password <> "different-suffix", ctx.context)
      assert {:error, :invalid} = Credentials.login(ctx.email, "x" <> password, ctx.context)
    end
  end

  test "verifies Ruby bcrypt when byte 72 splits a UTF-8 codepoint", ctx do
    password = String.duplicate("a", 71) <> String.duplicate("😀", 47)
    hash = "$2a$04$PhoenixA12eCorpusSaltukj1dGmqj3ckV/mj/SzCoeQ3gODjlSfG"
    refute String.valid?(binary_part(password, 0, 72))
    Repo.query!("UPDATE users SET encrypted_password=$1 WHERE id=$2", [hash, ctx.id])

    assert {:ok, result} = Credentials.login(ctx.email, password, ctx.context)
    assert result.user.id == ctx.id
    assert {:error, :invalid} = Credentials.login(ctx.email, "x" <> password, ctx.context)
  end

  test "strips only the whitespace Ruby's String#strip strips from the email", ctx do
    separator = <<0x2028::utf8>>

    assert {:error, :invalid} =
             Credentials.login(ctx.email <> separator, "safepassword12", ctx.context)

    assert {:ok, _} = Credentials.login("\t#{ctx.email}\v\r\n", "safepassword12", ctx.context)
  end

  test "matches the two failed strategy increments and generic unknown-user result", ctx do
    assert {:error, :invalid} = Credentials.login(ctx.email, "not-the-password", ctx.context)
    assert state(ctx.id).failed_attempts == @fixture["wrong_password"]["user"]["failed_attempts"]

    assert {:error, :invalid} =
             Credentials.login("unknown-a11@dawarich.test", "not-the-password", ctx.context)

    assert state(ctx.id).failed_attempts == 2
  end

  test "a correct password cannot bypass an existing lock", ctx do
    locked = DateTime.add(@now, -1800)
    Repo.query!("UPDATE users SET failed_attempts=10,locked_at=$1 WHERE id=$2", [locked, ctx.id])
    assert {:error, :invalid} = Credentials.login(ctx.email, "safepassword12", ctx.context)
    assert state(ctx.id).failed_attempts == 12
    assert state(ctx.id).locked_at == locked
  end

  test "expired locks are cleared before a rejected password and two new increments", ctx do
    Repo.query!(
      "UPDATE users SET failed_attempts=10,locked_at=$1,unlock_token='synthetic' WHERE id=$2",
      [DateTime.add(@now, -7200), ctx.id]
    )

    assert {:error, :invalid} = Credentials.login(ctx.email, "not-the-password", ctx.context)

    assert state(ctx.id) == %{
             failed_attempts: 2,
             locked_at: nil,
             unlock_token: nil,
             sign_in_count: 0,
             remember_created_at: nil
           }
  end

  test "new lock creation stays on the unlock-mail Rails boundary before any native effect",
       ctx do
    Repo.query!("UPDATE users SET failed_attempts=9 WHERE id=$1", [ctx.id])
    before = state(ctx.id)

    assert {:handoff, :lock_creation} =
             Credentials.login(ctx.email, "safepassword12", ctx.context)

    assert state(ctx.id) == before
  end

  test "OTP-required users are handed back before authentication effects", ctx do
    Repo.query!("UPDATE users SET otp_required_for_login=true WHERE id=$1", [ctx.id])
    before = state(ctx.id)
    assert {:handoff, :otp} = Credentials.login(ctx.email, "safepassword12", ctx.context)
    assert state(ctx.id) == before
  end

  test "a wrong or blank password for OTP, OAuth-linked and pending-payment accounts stays native with Rails' increments",
       ctx do
    for {name, password} <- [
          {"otp_wrong_password", "not-the-password"},
          {"otp_blank_password", ""},
          {"oauth_wrong_password", "not-the-password"},
          {"pending_payment_wrong_password", "not-the-password"}
        ] do
      reset(ctx.id, @fixture[name]["setup"])
      assert {:error, :invalid} = Credentials.login(ctx.email, password, ctx.context), name
      assert state(ctx.id).failed_attempts == @fixture[name]["user"]["failed_attempts"], name
    end
  end

  test "a correct password for an OAuth-linked or pending-payment account hands back without effects",
       ctx do
    for {setup, reason} <- [
          {%{"provider" => "github", "uid" => "native-a11"}, :provider},
          {%{"status" => 3}, :payment}
        ] do
      reset(ctx.id, setup)
      before = state(ctx.id)
      assert {:handoff, ^reason} = Credentials.login(ctx.email, "safepassword12", ctx.context)
      assert state(ctx.id) == before
    end
  end

  test "a correct password for a locked OTP account reaches Rails' OTP challenge", ctx do
    locked = DateTime.add(@now, -1800)

    Repo.query!(
      "UPDATE users SET otp_required_for_login=true,failed_attempts=10,locked_at=$1 WHERE id=$2",
      [locked, ctx.id]
    )

    before = state(ctx.id)
    assert {:handoff, :otp} = Credentials.login(ctx.email, "safepassword12", ctx.context)
    assert state(ctx.id) == before
    assert {:error, :invalid} = Credentials.login(ctx.email, "not-the-password", ctx.context)
    assert state(ctx.id).failed_attempts == 12
  end

  test "deleted accounts are absent and a blank password matches its single strategy failure",
       ctx do
    assert {:error, :invalid} = Credentials.login(ctx.email, "", ctx.context)

    increment =
      @fixture["blank_password"]["user"]["failed_attempts"] -
        @fixture["wrong_password"]["user"]["failed_attempts"]

    assert state(ctx.id).failed_attempts == increment
    Repo.query!("UPDATE users SET deleted_at=$1 WHERE id=$2", [@now, ctx.id])
    assert {:error, :invalid} = Credentials.login(ctx.email, "safepassword12", ctx.context)
    assert state(ctx.id).failed_attempts == increment
  end

  test "logout revokes remembered credentials globally and preserves actual legacy Warden replay",
       ctx do
    assert {:ok, result} =
             Credentials.login(ctx.email, "safepassword12", Map.put(ctx.context, :remember, true))

    assert :ok = Credentials.logout(ctx.id, ctx.context)
    assert state(ctx.id).remember_created_at == nil
    assert Accounts.from_remember_cookie(result.remember, DateTime.add(@now, 10)) == nil
    key = [[ctx.id], binary_part(@password_hash, 0, 29)]
    assert %Accounts.User{id: id} = Accounts.from_session(%{"warden.user.user.key" => key}, @now)
    assert id == ctx.id
  end

  test "remember restoration performs authentication hooks and preserves token lifetime", ctx do
    assert {:ok, first} =
             Credentials.login(ctx.email, "safepassword12", Map.put(ctx.context, :remember, true))

    created = first.user.remember_created_at
    Repo.query!("UPDATE users SET failed_attempts=3 WHERE id=$1", [ctx.id])
    assert {:ok, restored} = Credentials.restore(first.remember, ctx.context)
    assert restored.user.sign_in_count == 2
    assert restored.user.failed_attempts == 0
    assert restored.user.last_sign_in_at == first.user.current_sign_in_at
    assert restored.user.remember_created_at == created
    assert restored.remember == nil
  end

  test "remember restoration after logout is refused without authentication effects", ctx do
    assert {:ok, first} =
             Credentials.login(ctx.email, "safepassword12", Map.put(ctx.context, :remember, true))

    assert :ok = Credentials.logout(ctx.id, ctx.context)
    before = state(ctx.id)
    assert {:error, :invalid} = Credentials.restore(first.remember, ctx.context)
    assert state(ctx.id) == before
  end

  test "two actual database sessions retain both rejected request increments", ctx do
    Ecto.Adapters.SQL.Sandbox.checkin(Repo)
    email = "parallel-#{ctx.email}"

    id =
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        %{rows: [[id]]} =
          Repo.query!(
            "INSERT INTO users(email,encrypted_password,status,created_at,updated_at) VALUES($1,$2,1,$3,$3) RETURNING id",
            [email, @password_hash, @now]
          )

        id
      end)

    owner = self()

    try do
      actors =
        for _ <- 1..2 do
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
              %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
              send(owner, {:database_session, self(), backend})

              receive do
                :authenticate -> Credentials.login(email, "not-the-password", ctx.context)
              after
                5000 -> raise "authentication actor admission timeout"
              end
            end)
          end)
        end

      assert_receive {:database_session, first_actor, first_backend}, 5000
      assert_receive {:database_session, second_actor, second_backend}, 5000
      assert first_backend != second_backend
      send(first_actor, :authenticate)
      send(second_actor, :authenticate)
      assert Enum.map(actors, &Task.await(&1, 10_000)) == [{:error, :invalid}, {:error, :invalid}]
      assert Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn -> state(id).failed_attempts end) == 4
    after
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("DELETE FROM users WHERE id=$1", [id])
      end)
    end
  end

  test "a password changed between the unlocked check and the row lock hands back without effects",
       ctx do
    Ecto.Adapters.SQL.Sandbox.checkin(Repo)
    email = "changed-#{ctx.email}"
    id = Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn -> insert(email) end)
    owner = self()

    try do
      blocker =
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
            Repo.transaction(fn ->
              Repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [id])
              send(owner, {:row_locked, self()})

              receive do
                {:change, hash} ->
                  Repo.query!("UPDATE users SET encrypted_password=$1 WHERE id=$2", [hash, id])
              after
                5000 -> raise "row lock holder timeout"
              end
            end)
          end)
        end)

      assert_receive {:row_locked, holder}, 5000

      actor =
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
            %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
            send(owner, {:database_session, backend})
            Credentials.login(email, "safepassword12", ctx.context)
          end)
        end)

      assert_receive {:database_session, backend}, 5000
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn -> await_lock_wait(backend) end)
      send(holder, {:change, Bcrypt.hash_pwd_salt("another-password12", log_rounds: 4)})
      Task.await(blocker, 10_000)
      assert Task.await(actor, 10_000) == {:handoff, :changed}

      assert Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn -> state(id) end) == %{
               failed_attempts: 0,
               locked_at: nil,
               unlock_token: nil,
               sign_in_count: 0,
               remember_created_at: nil
             }
    after
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("DELETE FROM users WHERE id=$1", [id])
      end)
    end
  end

  defp insert(email) do
    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO users(email,encrypted_password,status,created_at,updated_at) VALUES($1,$2,1,$3,$3) RETURNING id",
        [email, @password_hash, @now]
      )

    id
  end

  defp await_lock_wait(backend) do
    case Repo.query!("SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1", [backend]).rows do
      [["Lock"]] -> :ok
      _ -> await_lock_wait(backend)
    end
  end

  defp reset(id, setup) do
    Repo.query!(
      "UPDATE users SET failed_attempts=0,locked_at=NULL,otp_required_for_login=$2,provider=$3,uid=$4,status=$5 WHERE id=$1",
      [
        id,
        Map.get(setup, "otp_required_for_login", false),
        setup["provider"],
        setup["uid"],
        Map.get(setup, "status", 1)
      ]
    )
  end

  defp state(id) do
    %{rows: [[failed, locked, token, count, remembered]]} =
      Repo.query!(
        "SELECT failed_attempts,locked_at,unlock_token,sign_in_count,remember_created_at FROM users WHERE id=$1",
        [id]
      )

    %{
      failed_attempts: failed,
      locked_at: utc(locked),
      unlock_token: token,
      sign_in_count: count,
      remember_created_at: remembered
    }
  end

  defp utc(nil), do: nil
  defp utc(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
end
