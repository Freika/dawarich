defmodule DawarichWeb.Params do
  @moduledoc false

  def ruby_to_i(value) when is_binary(value) do
    case Regex.run(~r/\A\s*([+-]?\d+(?:_\d+)*)/, value) do
      [_, digits] -> digits |> String.replace("_", "") |> String.to_integer()
      nil -> 0
    end
  end

  def ruby_to_i(_value), do: 0
end
