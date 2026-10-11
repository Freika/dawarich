defmodule DawarichWeb.LocalizedTime do
  @moduledoc false
  defdelegate l(arg1, arg2, arg3), to: Dawarich.Formatting.LocalizedTime
end
