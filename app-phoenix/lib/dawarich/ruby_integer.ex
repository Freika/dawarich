defmodule Dawarich.RubyInteger do
  @moduledoc false

  def to_i(value) when is_integer(value), do: value
  def to_i(value) when is_float(value), do: trunc(value)

  def to_i(value) when is_binary(value) do
    case Integer.parse(String.trim_leading(value)) do
      {number, _rest} -> number
      :error -> 0
    end
  end

  def to_i(_value), do: 0
end
