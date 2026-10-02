defmodule Dawarich.RailsCache.Marshal do
  @moduledoc "Ruby Marshal4.8 wire data without executing Ruby or resolving class constants."
  defdelegate decode(bytes), to: Dawarich.RailsCache.MarshalReader
  defdelegate encode(value), to: Dawarich.RailsCache.MarshalWriter
end
