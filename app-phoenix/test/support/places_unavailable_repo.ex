defmodule Dawarich.Test.PlacesUnavailableRepo do
  def query!(_sql, _params, _opts \\ []), do: raise("synthetic database failure")
end
