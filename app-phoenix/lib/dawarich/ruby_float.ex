defmodule Dawarich.RubyFloat do
  @moduledoc false

  def round(x, digits) when is_float(x) and is_integer(digits) and digits > 0 do
    cond do
      x == 0.0 -> x
      underflow?(x, digits) -> 0.0
      overflow?(x, digits) -> x
      true -> half_up(x, :math.pow(10, digits))
    end
  end

  defp underflow?(x, digits) do
    <<_sign::1, exponent::11, _fraction::52>> = <<x::float-64>>
    binexp = exponent - 1022
    exponent == 0 or digits < -if(binexp > 0, do: div(binexp, 3) + 1, else: div(binexp, 4))
  end

  defp overflow?(x, digits) do
    <<_sign::1, exponent::11, _fraction::52>> = <<x::float-64>>
    binexp = exponent - 1022
    digits >= 17 - if(binexp > 0, do: div(binexp, 4), else: div(binexp, 3) - 1)
  end

  defp half_up(x, scale) do
    rounded = :erlang.round(x * scale) * 1.0
    rounded = if rounded == 0.0 and x < 0, do: -0.0, else: rounded

    rounded =
      cond do
        x > 0 and (rounded + 0.5) / scale <= x -> rounded + 1
        x < 0 and (rounded - 0.5) / scale >= x -> rounded - 1
        true -> rounded
      end

    rounded / scale
  end
end
