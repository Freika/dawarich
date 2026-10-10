defmodule Dawarich.DataCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Dawarich.Repo

  using do
    quote do
      alias Dawarich.Repo
      alias Dawarich.Repo, as: ScratchRepo
      import Dawarich.DataCase
      import Dawarich.IngestCase, only: [user!: 0, user!: 1, commands: 0]
    end
  end

  setup context do
    setup_sandbox(context)
  end

  def setup_sandbox(context) do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    unless context[:async], do: Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  def rows(sql, params \\ []), do: Repo.query!(sql, params, log: false).rows
end
