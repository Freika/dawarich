defmodule Dawarich.Auth.AccountChangesTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.{Account, AccountChanges}
  alias Dawarich.Repo

  @now ~U[2026-10-04 00:00:00.000000Z]
  @password "a11rest-password-42"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    hash = Bcrypt.hash_pwd_salt(@password, log_rounds: 4)
    email = "a11rest-#{System.unique_integer([:positive])}@dawarich.test"

    [[id]] =
      Repo.query!(
        """
        INSERT INTO users(email,encrypted_password,api_key,status,settings,
          reset_password_token,reset_password_sent_at,failed_attempts,failed_otp_attempts,
          otp_locked_at,remember_created_at,sign_in_count,created_at,updated_at)
        VALUES($1,$2,'a11rest-key',1,$3,'a11rest-reset',$4,2,3,$4,$4,7,$4,$4) RETURNING id
        """,
        [email, hash, %{"timezone" => "Europe/Berlin"}, DateTime.add(@now, -86_400)],
        log: false
      ).rows

    %{
      id: id,
      email: email,
      salt: binary_part(hash, 0, 29),
      context: %{self_hosted: true, clock: fn -> @now end}
    }
  end

  test "rejects local updates without a valid current password before writes", c do
    assert Code.ensure_loaded?(AccountChanges)
    params = %{"email" => "a11rest-changed@dawarich.test"}

    for current <- [nil, "", "wrong-password"] do
      before = snapshot(c.id)
      input = if is_nil(current), do: params, else: Map.put(params, "current_password", current)
      assert {:error, render} = AccountChanges.update(c.id, c.salt, input, c.context)
      assert Enum.map(render.errors, &elem(&1, 0)) == [:current_password]
      assert render.email == params["email"]
      unchanged = snapshot(c.id) == before
      assert unchanged
      refute Map.has_key?(render, :current_password)
    end

    no_op = %{"email" => c.email, "current_password" => ""}
    assert {:error, _} = AccountChanges.update(c.id, c.salt, no_op, c.context)
    before = snapshot(c.id)

    assert {:ok, %Account{}} =
             AccountChanges.update(
               c.id,
               c.salt,
               %{no_op | "current_password" => @password},
               c.context
             )

    unchanged = snapshot(c.id) == before
    assert unchanged

    unsupported = [
      {"deleted_at", @now, :actor},
      {"locked_at", @now, :locked},
      {"provider", "github", :provider},
      {"otp_required_for_login", true, :otp},
      {"status", 3, :payment},
      {"settings", %{"immich_url" => "https://immich.a11rest.test///"}, :settings_callback},
      {"settings", %{"photoprism_url" => 5}, :settings_callback},
      {"settings", %{"maps" => %{"url" => " padded "}}, :settings_callback}
    ]

    for {field, value, reason} <- unsupported do
      [[original]] =
        Repo.query!("SELECT #{field} FROM users WHERE id=$1", [c.id], log: false).rows

      Repo.query!("UPDATE users SET #{field}=$1 WHERE id=$2", [value, c.id], log: false)
      before = snapshot(c.id)
      input = Map.put(params, "current_password", @password)
      assert {:handoff, ^reason} = AccountChanges.update(c.id, c.salt, input, c.context)
      unchanged = snapshot(c.id) == before
      assert unchanged
      Repo.query!("UPDATE users SET #{field}=$1 WHERE id=$2", [original, c.id], log: false)
    end

    before = snapshot(c.id)
    assert {:handoff, :actor} = AccountChanges.update(-1, c.salt, params, c.context)
    assert {:handoff, :session} = AccountChanges.update(c.id, "stale-salt", params, c.context)

    assert {:handoff, :cloud} =
             AccountChanges.update(c.id, c.salt, params, %{c.context | self_hosted: false})

    assert {:handoff, :oidc} =
             AccountChanges.update(c.id, c.salt, params, Map.put(c.context, :oidc, true))

    unchanged = snapshot(c.id) == before
    assert unchanged
  end

  defp snapshot(id) do
    [[row]] = Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [id], log: false).rows
    [[jobs]] = Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows
    [[mail_jobs]] = Repo.query!("SELECT count(*) FROM oban.oban_jobs", [], log: false).rows
    {row, jobs, mail_jobs}
  end

  test "email changes clear reset credentials but preserve password and login state", c do
    before = snapshot(c.id)
    input = %{"email" => " #{String.upcase(c.email)} ", "current_password" => @password}
    assert {:ok, user} = AccountChanges.update(c.id, c.salt, input, c.context)
    assert user.email == c.email
    unchanged = snapshot(c.id) == before
    assert unchanged

    input = %{input | "email" => " A11REST-UPDATED@dawarich.test "}
    assert {:ok, user} = AccountChanges.update(c.id, c.salt, input, c.context)
    assert user.email == "a11rest-updated@dawarich.test"
    reset_cleared = is_nil(user.reset_password_token) and is_nil(user.reset_password_sent_at)
    assert reset_cleared
    after_row = snapshot(c.id)

    oracle =
      "test/fixtures/auth/account/requests.json"
      |> File.read!()
      |> Jason.decode!()
      |> Enum.find(&(&1["name"] == "email_only"))

    assert changed(before, after_row) == oracle["changed"]
    same_hash = elem(before, 0)["encrypted_password"] == elem(after_row, 0)["encrypted_password"]
    assert same_hash
    assert user.updated_at == @now
    assert elem(before, 1) == elem(after_row, 1)
    assert elem(before, 2) == elem(after_row, 2)

    user_from_session =
      Dawarich.Accounts.from_session(%{"warden.user.user.key" => [[c.id], c.salt]}, @now)

    assert user_from_session.id == c.id
  end

  test "email collisions leave both actors unchanged", c do
    [[other_id]] =
      Repo.query!(
        """
        INSERT INTO users(email,encrypted_password,status,created_at,updated_at)
        SELECT 'a11rest-collision@dawarich.test',encrypted_password,1,created_at,updated_at
        FROM users WHERE id=$1 RETURNING id
        """,
        [c.id],
        log: false
      ).rows

    input = %{"email" => String.upcase(c.email), "current_password" => @password}
    before = snapshot(c.id)
    assert {:ok, _} = AccountChanges.update(c.id, c.salt, input, c.context)
    unchanged = snapshot(c.id) == before
    assert unchanged

    for deleted_at <- [nil, @now] do
      Repo.query!("UPDATE users SET deleted_at=$1 WHERE id=$2", [deleted_at, other_id],
        log: false
      )

      before = snapshot(c.id)
      other_before = snapshot(other_id)
      input = %{input | "email" => "A11REST-COLLISION@dawarich.test"}
      assert {:error, render} = AccountChanges.update(c.id, c.salt, input, c.context)
      assert render.messages == ["Email has already been taken"]
      unchanged = snapshot(c.id) == before and snapshot(other_id) == other_before
      assert unchanged
    end
  end

  defp changed({before, _, _}, {after_row, _, _}) do
    before |> Map.keys() |> Enum.reject(&(before[&1] == after_row[&1])) |> Enum.sort()
  end

  test "password updates preserve source side effects and invalidate old salts", c do
    initial = Repo.get!(Account, c.id)
    corpus = "test/fixtures/auth/account/requests.json" |> File.read!() |> Jason.decode!()

    for {kind, password} <- [
          {"password_only", "a11rest-new-password"},
          {"both", "a11rest-both-password"},
          {"password_only", String.duplicate("ü", 128)}
        ] do
      Repo.query!(
        """
        UPDATE users SET email=$1,encrypted_password=$2,reset_password_token='a11rest-reset',
          reset_password_sent_at=$3,updated_at=$3 WHERE id=$4
        """,
        [c.email, initial.encrypted_password, DateTime.add(@now, -86_400), c.id],
        log: false
      )

      before = snapshot(c.id)
      remember = [[c.id], c.salt, DateTime.to_iso8601(@now)]
      accepted_before = Dawarich.Auth.RememberCredential.valid?(initial, remember, @now)
      assert accepted_before
      email = if kind == "both", do: "A11REST-COMBINED@dawarich.test", else: c.email

      input = %{
        "email" => email,
        "current_password" => @password,
        "password" => password,
        "password_confirmation" => password
      }

      assert {:ok, user} = AccountChanges.update(c.id, c.salt, input, c.context)

      new_valid =
        Bcrypt.verify_pass(
          binary_part(password, 0, min(byte_size(password), 72)),
          user.encrypted_password
        )

      old_valid = Bcrypt.verify_pass(@password, user.encrypted_password)
      assert new_valid
      refute old_valid
      oracle = Enum.find(corpus, &(&1["name"] == kind))
      assert bcrypt_cost(user.encrypted_password) == oracle["bcrypt_cost"]
      after_row = snapshot(c.id)
      assert changed(before, after_row) == oracle["changed"]
      assert elem(before, 1) == elem(after_row, 1)
      assert elem(before, 2) == elem(after_row, 2)
      salt_changed = binary_part(user.encrypted_password, 0, 29) != c.salt
      assert salt_changed

      old_session_accepted =
        not is_nil(
          Dawarich.Accounts.from_session(%{"warden.user.user.key" => [[c.id], c.salt]}, @now)
        )

      refute old_session_accepted
      old_remember_accepted = Dawarich.Auth.RememberCredential.valid?(user, remember, @now)
      refute old_remember_accepted
    end

    user = Repo.get!(Account, c.id)
    salt = binary_part(user.encrypted_password, 0, 29)
    before = snapshot(c.id)

    for input <- [
          %{
            "email" => "a11rest-unsaved@dawarich.test",
            "current_password" => "wrong",
            "password" => "short"
          },
          %{
            "email" => "<bad>",
            "current_password" => String.duplicate("ü", 128),
            "password" => "short"
          }
        ] do
      assert {:error, _} = AccountChanges.update(c.id, salt, input, c.context)
      unchanged = snapshot(c.id) == before
      assert unchanged
    end
  end

  defp bcrypt_cost(hash) do
    hash |> String.split("$") |> Enum.at(2) |> String.to_integer()
  end
end
