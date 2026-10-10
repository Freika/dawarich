defmodule Dawarich.Test.PlacesTagFailureRepo do
  defdelegate transaction(fun), to: Dawarich.Repo

  def query!(sql, params, opts \\ []) do
    if String.contains?(sql, "INSERT INTO taggings"), do: raise("synthetic tag phase failure")
    Dawarich.Repo.query!(sql, params, opts)
  end
end

defmodule Dawarich.Test.PlacesRevokingRepo do
  defdelegate transaction(fun), to: Dawarich.Repo

  def query!(sql, params, opts \\ []) do
    result = Dawarich.Repo.query!(sql, params, opts)

    if String.contains?(sql, "FROM places WHERE") and String.contains?(sql, "FOR UPDATE") do
      Dawarich.Repo.query!(
        "UPDATE users SET encrypted_password=$1 WHERE id=$2",
        [String.duplicate("x", 60), List.last(params)], log: false)
    end

    result
  end
end
