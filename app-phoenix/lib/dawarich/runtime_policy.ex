defmodule Dawarich.RuntimePolicy do
  @moduledoc false
  defdelegate self_hosted?(), to: DawarichWeb.LayoutAssigns
  defdelegate self_hosted?(env), to: DawarichWeb.LayoutAssigns
end
