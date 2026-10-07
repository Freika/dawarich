defmodule Dawarich.Transaction do
  @moduledoc false

  def run(repo, fun, opts \\ []), do: repo.transaction(fun, options(repo, opts))

  def options(repo, opts \\ []) do
    if repo.in_transaction?(),
      do: Keyword.put(opts, :mode, :savepoint),
      else: Keyword.delete(opts, :mode)
  end
end
