defmodule Dawarich.Test.PlacesCommitAckFailureRepo do
  def transaction(fun) do
    Dawarich.Repo.transaction(fun)
    raise "synthetic transaction acknowledgement failure"
  end

  defdelegate query!(sql, params, opts), to: Dawarich.Repo
end
