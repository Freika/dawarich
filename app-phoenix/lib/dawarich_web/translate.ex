defmodule DawarichWeb.Translate do
  @moduledoc false
  defdelegate t(arg1, arg2, arg3), to: Dawarich.Formatting.Translate
  defdelegate t(arg1, arg2, arg3, arg4), to: Dawarich.Formatting.Translate
end
