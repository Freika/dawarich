defmodule Dawarich.Test.CredentialCrashRepo do
  def transaction(_fun), do: raise(ArgumentError, "synthetic credential write crash")
  def query!(_sql, _params, _opts), do: raise(ArgumentError, "synthetic credential write crash")
end
