defmodule Dawarich.IngestCaseIsolationTest do
  use Dawarich.IngestCase, async: true

  test "async setup does not share its sandbox connection with unrelated processes" do
    parent = self()

    spawn(fn ->
      result =
        try do
          Repo.query!("SELECT 1", [], log: false)
          :connected
        rescue
          DBConnection.OwnershipError -> :not_owned
        end

      send(parent, {:unrelated, result})
    end)

    assert_receive {:unrelated, :not_owned}, 5_000
  end

  test "async setup holds no table lock on the control tables" do
    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)::int FROM pg_locks l JOIN pg_class c ON c.oid = l.relation
               JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE l.pid = pg_backend_pid() AND n.nspname = 'phoenix'
                 AND l.mode NOT IN ('AccessShareLock', 'RowExclusiveLock')
               """,
               [],
               log: false
             ).rows
  end
end
