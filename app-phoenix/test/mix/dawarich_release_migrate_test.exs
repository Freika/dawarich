defmodule Mix.Tasks.Dawarich.ReleaseMigrateTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Dawarich.ReleaseMigrate

  test "a database below the 1.0.0 floor is refused with the release it lacks and the remedy" do
    assert ReleaseMigrate.describe({:below_floor, "0.37.0"}) ==
             "refused: this database has not reached Dawarich 0.37.0, and this image upgrades only from 1.0.0; " <>
               "start the Dawarich 1.15.2 image once so Rails upgrades it, then start this image"
  end

  test "a ledger with no Dawarich migration at all is refused with the version count and DATABASE_NAME hint" do
    assert ReleaseMigrate.describe({:not_dawarich, 3}) ==
             "refused: schema_migrations holds 3 versions and none of them is a Dawarich migration; check DATABASE_NAME"
  end
end
