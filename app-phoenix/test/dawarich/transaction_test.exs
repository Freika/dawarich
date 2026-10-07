defmodule Dawarich.TransactionTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Repo, Transaction}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
    :ok
  end

  @tag :transaction_boundaries
  test "shared transactions start on idle connections and isolate nested SQL failures" do
    refute Repo.in_transaction?()
    assert {:ok, true} = Transaction.run(Repo, fn -> Repo.in_transaction?() end)
    assert {:error, :cancelled} = Transaction.run(Repo, fn -> Repo.rollback(:cancelled) end)

    assert {:ok, :ok} =
             Repo.transaction(fn ->
               assert {:ok, true} = Transaction.run(Repo, fn -> Repo.in_transaction?() end)

               assert_raise Postgrex.Error, fn ->
                 Repo.query!("SELECT 1/0", [], Transaction.options(Repo, log: false))
               end

               assert Repo.query!("SELECT 1", [], log: false).rows == [[1]]
               :ok
             end)
  end

  @tag :savepoint_guard
  test "savepoint mode is confined to the shared transaction helper" do
    root = Path.expand("../../lib", __DIR__)

    offenders =
      Path.wildcard(root <> "/**/*.ex")
      |> Enum.reject(&(Path.relative_to(&1, root) == "dawarich/transaction.ex"))
      |> Enum.filter(&(File.read!(&1) =~ ~r/mode:\s*:savepoint/))

    assert offenders == []
  end
end
