defmodule Dawarich.Auth.Recovery.ConcurrencyTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.Recovery.{Lifecycle, Token}
  alias Dawarich.Repo
  @now ~U[2026-10-01 12:00:00.000000Z]
  @races Jason.decode!(
           File.read!(Path.expand("../../../fixtures/auth/recovery/races.json", __DIR__))
         )
  @fields ~w(reset_password_token reset_password_sent_at unlock_token locked_at failed_attempts
             failed_otp_attempts otp_locked_at sign_in_count current_sign_in_at last_sign_in_at)

  defp context,
    do: %{
      secret: "phoenix-a2-cookie-fixture-secret-not-for-production",
      clock: fn -> @now end,
      log_rounds: 4,
      self_hosted: true
    }

  defmodule CoordinatedRepo do
    defdelegate transaction(fun), to: Dawarich.Repo
    defdelegate update!(changeset), to: Dawarich.Repo
    defdelegate exists?(query), to: Dawarich.Repo

    def one(query) do
      user = Dawarich.Repo.one(query)
      send(Process.get(:race_owner), {:looked_up, self()})

      receive do
        :continue -> user
      after
        5000 -> raise "post-lookup timeout"
      end
    end
  end

  test "two post-lookup reset calls both succeed and leave the Rails race state" do
    row = @races["reset"]
    id = insert(row)

    results =
      overlapped(fn index ->
        Lifecycle.reset(
          row["raw"],
          "race-password-#{index}",
          nil,
          Map.merge(context(), %{repo: CoordinatedRepo, sign_in_ip: "127.0.0.#{index + 1}"})
        )
      end)

    assert Enum.map(results, &match?({:ok, _}, &1)) == Enum.map(row["calls"], & &1["success"])
    final = persisted(id)
    assert state(final) == row["final"]
    assert final.current_sign_in_ip in ["127.0.0.1", "127.0.0.2"]

    {:ok, winner} =
      Enum.find(results, fn {:ok, user} -> user.encrypted_password == final.encrypted_password end)

    assert final.current_sign_in_ip == winner.current_sign_in_ip
    index = if final.current_sign_in_ip == "127.0.0.1", do: 0, else: 1
    assert Bcrypt.verify_pass("race-password-#{index}", final.encrypted_password)

    assert Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
             Lifecycle.reset(row["raw"], "another-password12", nil, context())
           end) == {:error, :invalid}
  end

  test "two post-lookup unlock calls both succeed and leave the Rails race state" do
    row = @races["unlock"]
    id = insert(row)

    results =
      overlapped(fn _ ->
        Lifecycle.unlock(row["raw"], Map.put(context(), :repo, CoordinatedRepo))
      end)

    assert Enum.map(results, &match?({:ok, _}, &1)) == Enum.map(row["calls"], & &1["success"])
    assert state(persisted(id)) == row["final"]

    assert Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
             Lifecycle.unlock(row["raw"], context())
           end) == {:error, :invalid}
  end

  defp insert(row) do
    before = row["before"]
    column = if before["unlock_token"], do: :unlock_token, else: :reset_password_token
    digest = Token.digest(column, row["raw"], context().secret)
    assert digest == Enum.join(before[Atom.to_string(column)])
    time = fn key -> before[key] && elem(DateTime.from_iso8601(before[key]), 1) end

    id =
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        [[id]] =
          Repo.query!(
            """
            INSERT INTO users(email,reset_password_token,reset_password_sent_at,unlock_token,locked_at,
              failed_attempts,failed_otp_attempts,otp_locked_at,sign_in_count,created_at,updated_at)
            VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$10) RETURNING id
            """,
            [
              "race-#{System.unique_integer([:positive])}@dawarich.test",
              if(column == :reset_password_token, do: digest),
              time.("reset_password_sent_at"),
              if(column == :unlock_token, do: digest),
              time.("locked_at"),
              before["failed_attempts"],
              before["failed_otp_attempts"],
              time.("otp_locked_at"),
              before["sign_in_count"],
              @now
            ]
          ).rows

        id
      end)

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("DELETE FROM users WHERE id=$1", [id])
      end)
    end)

    id
  end

  defp state(user) do
    Map.new(@fields, fn field ->
      value = Map.fetch!(user, String.to_existing_atom(field))
      {field, if(match?(%DateTime{}, value), do: DateTime.to_iso8601(value), else: value)}
    end)
  end

  defp persisted(id),
    do: Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn -> Repo.get!(Account, id) end)

  defp overlapped(fun) do
    owner = self()

    actors =
      for index <- 0..1 do
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
            Process.put(:race_owner, owner)
            [[backend]] = Repo.query!("SELECT pg_backend_pid()").rows
            send(owner, {:overlap_backend, backend})
            fun.(index)
          end)
        end)
      end

    assert_receive {:overlap_backend, pid1}, 5000
    assert_receive {:overlap_backend, pid2}, 5000
    assert pid1 != pid2
    assert_receive {:looked_up, first}, 5000
    assert_receive {:looked_up, second}, 5000
    send(first, :continue)
    send(second, :continue)
    Enum.map(actors, &Task.await(&1, 10_000))
  end
end
