defmodule DawarichWeb.NumberFormat do
  @moduledoc false
  defdelegate delimited(arg1, arg2), to: Dawarich.Formatting.NumberFormat
  defdelegate precision_one(arg1, arg2), to: Dawarich.Formatting.NumberFormat
  defdelegate with_precision_one(arg1, arg2), to: Dawarich.Formatting.NumberFormat
end
