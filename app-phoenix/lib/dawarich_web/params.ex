defmodule DawarichWeb.Params do
  @moduledoc false
  defdelegate ruby_to_i(arg1), to: Dawarich.Formatting.Params
  defdelegate to_query(arg1), to: Dawarich.Formatting.Params
  defdelegate to_query(arg1, arg2), to: Dawarich.Formatting.Params
end
