defmodule Dawarich.Transaction do
  @moduledoc false

  def run(repo, fun, opts \\ []) do
    if repo.in_transaction?(),
      do: nested(repo, fun, Keyword.delete(opts, :mode)),
      else: repo.transaction(fun, Keyword.delete(opts, :mode))
  end

  def options(repo, opts \\ []) do
    if repo.in_transaction?(),
      do: Keyword.put(opts, :mode, :savepoint),
      else: Keyword.delete(opts, :mode)
  end

  defp nested(repo, fun, opts) do
    name = "dawarich_#{System.unique_integer([:positive])}"
    repo.query!("SAVEPOINT #{name}", [], opts)

    try do
      result = fun.()
      repo.query!("RELEASE SAVEPOINT #{name}", [], opts)
      {:ok, result}
    catch
      :throw, {DBConnection, _ref, reason} ->
        recover(repo, name, opts)
        {:error, reason}

      kind, reason ->
        stack = __STACKTRACE__
        recover(repo, name, opts)
        :erlang.raise(kind, reason, stack)
    end
  end

  defp recover(repo, name, opts) do
    repo.query!("ROLLBACK TO SAVEPOINT #{name}", [], opts)
    repo.query!("RELEASE SAVEPOINT #{name}", [], opts)
  end
end
