defmodule DawarichWeb.LocalizedDate do
  @moduledoc false
  defdelegate l(arg1, arg2, arg3), to: Dawarich.Formatting.LocalizedDate
  defdelegate month_name(arg1, arg2, arg3), to: Dawarich.Formatting.LocalizedDate
  defdelegate abbr_month(arg1, arg2), to: Dawarich.Formatting.LocalizedDate
  defdelegate time(arg1, arg2, arg3), to: Dawarich.Formatting.LocalizedDate
end
