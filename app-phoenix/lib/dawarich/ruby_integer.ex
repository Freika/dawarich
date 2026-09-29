defmodule Dawarich.RubyInteger do
  @moduledoc false

  def to_i(value) when is_integer(value), do: value
  def to_i(value) when is_float(value), do: trunc(value)

  def to_i(value) when is_binary(value) do
    case Regex.run(~r/\A[\t\n\x0B\f\r ]*([+-]?[0-9]+(?:_[0-9]+)*)/, value,
           capture: :all_but_first
         ) do
      [digits] -> digits |> String.replace("_", "") |> String.to_integer()
      nil -> 0
    end
  end

  def to_i(_value), do: 0
end
