defmodule Dawarich.Test.LaterFailureRepo do
  defdelegate transaction(fun), to: Dawarich.Repo

  def query!(sql, params, opts) do
    if String.starts_with?(sql, "INSERT INTO instance_settings") and
         hd(params) == "reverse_geocoding_rps",
       do: raise("synthetic later persistence failure"),
       else: Dawarich.Repo.query!(sql, params, opts)
  end
end
