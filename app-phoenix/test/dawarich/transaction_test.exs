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

  @tag :recoverable_callback
  test "nested callback rollback removes inner writes while outer writes commit" do
    Repo.query!("CREATE TEMP TABLE callback_markers(label text)", [], log: false)

    try do
      assert {:ok, :handled} =
               Repo.transaction(fn ->
                 Repo.query!("INSERT INTO callback_markers VALUES('outer')", [], log: false)

                 assert {:error, :inner_failed} =
                          Transaction.run(Repo, fn ->
                            Repo.query!("INSERT INTO callback_markers VALUES('inner')", [],
                              log: false
                            )

                            Repo.rollback(:inner_failed)
                          end)

                 assert {:ok, :nested} =
                          Transaction.run(Repo, fn ->
                            assert {:error, :deeper_failed} =
                                     Transaction.run(Repo, fn ->
                                       Repo.query!(
                                         "INSERT INTO callback_markers VALUES('deeper')",
                                         [],
                                         log: false
                                       )

                                       Repo.rollback(:deeper_failed)
                                     end)

                            :nested
                          end)

                 assert Repo.query!("SELECT 1", [], log: false).rows == [[1]]
                 :handled
               end)

      assert Repo.query!("SELECT label FROM callback_markers", [], log: false).rows == [["outer"]]
    after
      Repo.query!("DROP TABLE IF EXISTS callback_markers", [], log: false)
    end
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
