defmodule Dawarich.RailsCache.Value do
  @moduledoc "Ruby wire values are data; decoding never loads or constructs Ruby classes."
  defstruct [:tag, :class, :value, ivars: []]
end
