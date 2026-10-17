defmodule Dawarich.Imports.Fence do
  @moduledoc false

  def run(context, fun) do
    case Map.get(context, :fence) do
      nil -> fun.()
      fence -> fence.(fun)
    end
  end
end
