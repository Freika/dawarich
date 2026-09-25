defmodule Mix.Tasks.Dawarich.ReleaseMigrateTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Dawarich.ReleaseMigrate

  @harness_failed_version ~r/failed [^ ]* ([0-9]+):/
  @harness_refusal ~r/refused: this database has not reached Dawarich ([^,]+),/

  test "a database below the 1.0.0 floor is refused with the release it lacks and the remedy" do
    message = ReleaseMigrate.describe({:below_floor, "0.37.0"})

    assert message ==
             "refused: this database has not reached Dawarich 0.37.0, and this image upgrades only from 1.0.0; " <>
               "start the Dawarich 1.15.2 image once so Rails upgrades it, then start this image"

    assert [_, "0.37.0"] = Regex.run(@harness_refusal, "** (Mix) " <> message)
  end

  test "a ledger with no Dawarich migration at all is refused with the version count and DATABASE_NAME hint" do
    assert ReleaseMigrate.describe({:not_dawarich, 3}) ==
             "refused: schema_migrations holds 3 versions and none of them is a Dawarich migration; check DATABASE_NAME"
  end

  test "a failure names the release and version the way ecto_check.sh parses them" do
    message =
      ReleaseMigrate.describe(
        {:failed, "1.11.0", "20260730210150", "ERROR 23505\n  (unique_violation)"}
      )

    assert message == "failed 1.11.0 20260730210150: ERROR 23505 (unique_violation)"
    assert [_, "20260730210150"] = Regex.run(@harness_failed_version, "** (Mix) " <> message)
  end

  test "a connection error from the two-connection probe is refused with its message" do
    postgrex = %Postgrex.Error{message: "too many connections for role \"dawarich\""}
    connection = DBConnection.ConnectionError.exception("tcp recv: closed")

    assert ReleaseMigrate.describe(postgrex) ==
             "refused: too many connections for role \"dawarich\""

    assert ReleaseMigrate.describe(connection) == "refused: tcp recv: closed"
  end

  test "an unknown release is named the way the porting procedure expects" do
    assert ReleaseMigrate.describe({:unknown_release, "1.15.2"}) ==
             "no Ecto release module for 1.15.2"
  end
end
