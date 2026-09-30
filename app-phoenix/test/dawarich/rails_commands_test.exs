defmodule Dawarich.RailsCommandsTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.RailsCommands

  @payload %{"user_id" => 7, "started_at" => ["2026-06-15T10:00:00Z"]}

  test "insert! writes one row with the kind and the jsonb payload" do
    assert RailsCommands.insert!(ScratchRepo, "visit_months_changed", @payload) == :ok

    assert rows(
             "SELECT kind, payload->>'user_id', payload->'started_at'->>0 FROM phoenix.rails_commands"
           ) == [["visit_months_changed", "7", "2026-06-15T10:00:00Z"]]
  end

  test "insert! inside a caller transaction rolls back with it" do
    assert {:error, :x} =
             ScratchRepo.transaction(fn ->
               RailsCommands.insert!(ScratchRepo, "visit_months_changed", @payload)
               ScratchRepo.rollback(:x)
             end)

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  test "insert! refuses a payload without an integer user_id" do
    assert_raise FunctionClauseError, fn ->
      RailsCommands.insert!(ScratchRepo, "visit_months_changed", %{})
    end

    assert_raise FunctionClauseError, fn ->
      RailsCommands.insert!(ScratchRepo, "visit_months_changed", %{"user_id" => "7"})
    end
  end
end
