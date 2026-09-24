defmodule Dawarich.ReleaseMigrator.BaselineTest do
  use Dawarich.ScratchCase

  import Dawarich.ReleaseMigration

  alias Dawarich.{RailsTree, ReleaseMigrator}

  test "the shipped baseline builds the Rails schema and records every migration up to its newest" do
    assert {:ok, :ok} =
             ScratchRepo.transaction(
               fn -> sql!(ScratchRepo, ReleaseMigrator.baseline_sql()) end,
               timeout: :infinity
             )

    for table <- ~w[users points tracks schema_migrations ar_internal_metadata data_migrations] do
      assert table?(ScratchRepo, table), table
    end

    %{rows: rows} = ScratchRepo.query!("SELECT version FROM schema_migrations ORDER BY version")
    ledger = List.flatten(rows)
    assert ledger != []
    assert ledger == Enum.filter(RailsTree.versions("migrate"), &(&1 <= List.last(ledger)))
  end
end
