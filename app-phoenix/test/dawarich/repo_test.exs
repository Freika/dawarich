defmodule Dawarich.RepoTest do
  use ExUnit.Case, async: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
  end

  test "reads tables owned by the Rails schema" do
    %{rows: [[exists]]} =
      Dawarich.Repo.query!(
        "SELECT to_regclass('public.users') IS NOT NULL AND to_regclass('public.points') IS NOT NULL"
      )

    assert exists
  end

  test "sessions run in UTC set by the connection's startup parameter" do
    assert %{rows: [["UTC", "client"]]} =
             Dawarich.Repo.query!(
               "SELECT setting, source FROM pg_settings WHERE name = 'TimeZone'"
             )
  end
end
