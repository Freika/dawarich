defmodule Dawarich.Admin.UserCreateTest do
  use ExUnit.Case, async: false
  alias Dawarich.Admin.UserCreate
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser

  @now ~U[2024-02-29 23:30:00.000000Z]

  defmodule CallbackFailureRepo do
    defdelegate transaction(fun), to: Dawarich.Repo
    defdelegate rollback(reason), to: Dawarich.Repo

    def query!(sql, params, opts) do
      if String.starts_with?(sql, "UPDATE users SET status=1"),
        do: raise("synthetic activation failure"),
        else: Dawarich.Repo.query!(sql, params, opts)
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    RailsUser.insert!(%{id: 15001, email: "a10b-create-admin@example.invalid", admin: true})

    %{
      actor: Accounts.get(15001),
      context: %{self_hosted: true, locale: "en", clock: fn -> @now end}
    }
  end

  test "creates a nonadmin active pro user with Rails defaults and salted password", c do
    assert Code.ensure_loaded?(UserCreate), "admin user creation must exist"
    before = effects()

    for {email, password} <- [
          {" A10B-CREATED@example.invalid ", "a10b-create-password"},
          {"a10b-unicode@example.invalid", String.duplicate("ü", 128)}
        ] do
      assert {:ok, id} =
               UserCreate.call(
                 c.actor,
                 %{
                   "email" => email,
                   "password" => password,
                   "admin" => "1",
                   "status" => "inactive"
                 },
                 c.context
               )

      [[row]] = Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [id], log: false).rows
      assert row["email"] == String.downcase(String.trim(email))
      assert row["admin"] == false and row["status"] == 1 and row["plan"] == 1
      assert row["theme"] == "dark"

      assert row["settings"] == %{
               "fog_of_war_meters" => "100",
               "meters_between_routes" => "500",
               "minutes_between_routes" => "30"
             }

      assert row["sign_in_count"] == 0 and row["failed_attempts"] == 0 and
               row["failed_otp_attempts"] == 0

      assert is_nil(row["reset_password_token"]) and is_nil(row["remember_created_at"])
      key_valid = is_binary(row["api_key"]) and row["api_key"] =~ ~r/\A[0-9a-f]{64}\z/
      assert key_valid

      valid =
        Bcrypt.verify_pass(
          binary_part(password, 0, min(byte_size(password), 72)),
          row["encrypted_password"]
        )

      assert valid
      wrong = Bcrypt.verify_pass("wrong-password", row["encrypted_password"])
      refute wrong

      [[created, updated, expiry]] =
        Repo.query!("SELECT created_at,updated_at,active_until FROM users WHERE id=$1", [id],
          log: false
        ).rows

      assert created == DateTime.to_naive(@now) and updated == created
      assert expiry == ~N[3024-02-29 23:30:00.000000]
    end

    assert effects() == before

    assert_raise RuntimeError, "synthetic activation failure", fn ->
      UserCreate.call(
        c.actor,
        %{"email" => "a10b-partial@example.invalid", "password" => "a10b-create-password"},
        Map.put(c.context, :repo, CallbackFailureRepo)
      )
    end

    [[status, expiry, key]] =
      Repo.query!(
        "SELECT status,active_until,api_key FROM users WHERE email=$1",
        ["a10b-partial@example.invalid"],
        log: false
      ).rows

    assert status == 0 and is_nil(expiry)
    key_present = is_binary(key) and byte_size(key) == 64
    assert key_present
    assert effects() == before
    assert {:handoff, :cloud} = UserCreate.call(c.actor, %{}, %{c.context | self_hosted: false})

    Repo.query!("UPDATE users SET admin=false WHERE id=$1", [c.actor.id], log: false)
    before_count = Repo.query!("SELECT count(*) FROM users", [], log: false).rows

    assert {:handoff, :actor} =
             UserCreate.call(
               c.actor,
               %{"email" => "a10b-refused@example.invalid", "password" => "a10b-create-password"},
               c.context
             )

    assert Repo.query!("SELECT count(*) FROM users", [], log: false).rows == before_count
  end

  defp effects do
    Repo.query!(
      "SELECT (SELECT count(*) FROM job_outbox),(SELECT count(*) FROM oban.oban_jobs)",
      [],
      log: false
    ).rows
  end
end
