defmodule Dawarich.ReleaseMigrationsTest do
  use ExUnit.Case, async: true

  alias Dawarich.ReleaseMigrations
  alias Dawarich.ReleaseMigrations.Unreleased

  test "finds a registered release by name and keeps Unreleased last" do
    assert ReleaseMigrations.find("unreleased") == Unreleased
    assert ReleaseMigrations.find("0.0.0") == nil
    assert List.last(ReleaseMigrations.all()) == Unreleased
  end
end
