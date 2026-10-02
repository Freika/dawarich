defmodule Dawarich.Imports.DestroyLock do
  @moduledoc false
  def run(repo, id, fun) do
    if repo.in_transaction?(),
      do: raise(ArgumentError, "Import destruction cannot run inside a transaction")

    case Dawarich.State.Lease.with_lease(repo, "import:#{id}", fun, timeout_ms: 0) do
      {:ok, result} -> result
      {:error, :timeout} -> {:skip, :busy}
    end
  end
end
