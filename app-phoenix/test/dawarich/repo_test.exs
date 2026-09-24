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
end
