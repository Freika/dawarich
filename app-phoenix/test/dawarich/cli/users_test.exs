defmodule Dawarich.CLI.UsersTest do
  use Dawarich.JobsCase

  alias Dawarich.CLI
  alias Dawarich.CLI.Users
  alias Dawarich.{ScratchRepo, Wave6Fixtures}

  @login "phoenix-a12e-login-not-for-production"

  defp run(argv, stdin \\ "") do
    {:ok, out} = StringIO.open("")
    {:ok, err} = StringIO.open("")
    {:ok, input} = StringIO.open(stdin)
    code = CLI.run(argv, %{repo: ScratchRepo, out: out, err: err, stdin: input, env: %{}})
    prompted = err |> StringIO.contents() |> elem(1)

    {code, out |> StringIO.contents() |> elem(1),
     String.replace(prompted, "New password: \n", "")}
  end

  defp column(id, name), do: hd(hd(rows("SELECT #{name} FROM users WHERE id = $1", [id])))

  test "admin refuses a soft-deleted user" do
    Wave6Fixtures.user!(%{
      "email" => "gone@example.invalid",
      "deleted_at" => ~N[2026-01-01 00:00:00]
    })

    assert {1, "", "dawarich: no user with email gone@example.invalid\n"} =
             run(~w(users admin gone@example.invalid))
  end

  test "email validates like Devise and leaves an unchanged address untouched" do
    id =
      Wave6Fixtures.user!(%{
        "email" => "same@example.invalid",
        "updated_at" => ~N[2026-01-01 00:00:00]
      })

    Wave6Fixtures.user!(%{"email" => "taken@example.invalid"})

    assert {1, _, "dawarich: Email can't be blank\n"} =
             run(["users", "email", "same@example.invalid", "  "])

    assert {1, _, "dawarich: Email is invalid\n"} = run(~w(users email same@example.invalid nope))

    assert {1, _, "dawarich: Email has already been taken\n"} =
             run(~w(users email same@example.invalid TAKEN@example.invalid))

    assert {0, "same@example.invalid is now same@example.invalid\n", ""} =
             run(~w(users email SAME@example.invalid same@example.invalid))

    assert column(id, "updated_at") == ~N[2026-01-01 00:00:00.000000]
  end

  test "password length is Devise's 12 to 128 characters, counted as code points" do
    Wave6Fixtures.user!(%{"email" => "len@example.invalid"})

    assert {1, _, "dawarich: Password is too short (minimum is 12 characters)\n"} =
             run(~w(users password len@example.invalid), "elevenchars\n")

    assert {1, _, "dawarich: Password is too long (maximum is 128 characters)\n"} =
             run(~w(users password len@example.invalid), String.duplicate("a", 129) <> "\n")

    assert {0, _, _} =
             run(~w(users password len@example.invalid), String.duplicate("ä", 128) <> "\n")
  end

  test "the stored hash is Ruby's $2a$ bcrypt at cost 12" do
    id = Wave6Fixtures.user!(%{"email" => "hash@example.invalid"})
    assert {0, _, _} = run(~w(users password hash@example.invalid), @login <> "\n")
    hash = column(id, "encrypted_password")
    assert String.starts_with?(hash, "$2a$12$")
    assert Bcrypt.verify_pass(@login, hash)
  end

  test "the password is one stdin line without its newline; spaces are part of it; EOF is a usage error" do
    id = Wave6Fixtures.user!(%{"email" => "spaces@example.invalid"})
    assert {0, _, _} = run(~w(users password spaces@example.invalid), "  #{@login}  \r\n")
    assert Bcrypt.verify_pass("  #{@login}  ", column(id, "encrypted_password"))

    assert {1, _,
            "dawarich: usage: dawarich users password EMAIL, with the new password on standard input\n"} =
             run(~w(users password spaces@example.invalid))
  end

  test "never prints the password or its hash" do
    id = Wave6Fixtures.user!(%{"email" => "quiet@example.invalid"})
    {0, out, err} = run(~w(users password quiet@example.invalid), @login <> "\n")
    refute out <> err =~ @login
    refute out <> err =~ column(id, "encrypted_password")
    refute out <> err =~ "$2a$"
    assert out =~ "Password updated for quiet@example.invalid"
  end

  test "hash_password/1 is what R2 hands to Rails" do
    assert Bcrypt.verify_pass(@login, Users.hash_password(@login))
  end

  test "the corpus hash is hash_password/2 with the recorded salt, in hash_password/1's shape" do
    %{"hash" => recorded, "salt" => salt} =
      "../../fixtures/a12e/password.json"
      |> Path.expand(__DIR__)
      |> File.read!()
      |> Jason.decode!()

    assert Users.hash_password(@login, salt) == recorded
    assert <<"$2a$12$", _::binary-size(53)>> = Users.hash_password(@login)
    assert binary_part(recorded, 0, 7) == "$2a$12$" and byte_size(recorded) == 60
  end
end
