defmodule Dawarich.EnhancedImport.Adapters do
  @moduledoc false
  alias Dawarich.EnhancedImport.{
    Gpx,
    PhoneAdapter,
    PolarstepsAdapter,
    RecordsAdapter,
    SemanticAdapter
  }

  def reduce(path, %{source: 4}, _context, acc, fun), do: Gpx.reduce(path, acc, fun)

  def reduce(path, %{source: 3} = import, context, acc, fun),
    do: PhoneAdapter.reduce(path, import, context, acc, fun)

  def reduce(path, %{source: 0} = import, context, acc, fun),
    do: SemanticAdapter.reduce(path, import, context, acc, fun)

  def reduce(path, %{source: 2} = import, context, acc, fun),
    do: RecordsAdapter.reduce(path, import, context, acc, fun)

  def reduce(path, %{source: 13} = import, context, acc, fun),
    do: PolarstepsAdapter.reduce(path, import, context, acc, fun)
end
