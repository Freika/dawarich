defmodule Dawarich.Imports.DestroyLock do
  @moduledoc false
  def run(repo, id, fun) do
    if repo.in_transaction?(),
      do: raise(ArgumentError, "Import destruction cannot run inside a transaction")

    repo.checkout(
      fn ->
        key = "phoenix-import:#{id}"

        [[locked]] =
          repo.query!("SELECT pg_try_advisory_lock(hashtextextended($1,0))", [key], log: false).rows

        if locked do
          try do
            fun.()
          after
            repo.query!("SELECT pg_advisory_unlock(hashtextextended($1,0))", [key], log: false)
          end
        else
          {:skip, :busy}
        end
      end,
      timeout: :infinity
    )
  end
end
