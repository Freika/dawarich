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
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: not context[:async])
    ExUnit.Callbacks.on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    :ok
  end

  def rows(sql, params \\ []), do: Repo.query!(sql, params, log: false).rows
end
