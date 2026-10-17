defmodule Dawarich.RubyDecimal do
  @moduledoc false

  alias Dawarich.RubyFloat

  def fixed(x, digits) when is_float(x) and is_integer(digits) and digits >= 0 do
    <<sign::1, _rest::63>> = <<x::float>>
    {n, e} = shortest(x)

    q =
      if e + digits >= 0,
        do: n * Integer.pow(10, e + digits),
        else: half_even(n, Integer.pow(10, -(e + digits)))

    if(sign == 1, do: "-", else: "") <> render(q, digits)
  end

  def column(x, precision, scale) when is_float(x) and is_integer(scale) and scale > 0 do
    rounded = RubyFloat.round(x, scale)
    {n, e} = shortest(rounded)
    {m, e} = significant(n, e, min(precision, 16))

    q =
      if e + scale >= 0,
        do: m * Integer.pow(10, e + scale),
        else: half_up(m, Integer.pow(10, -(e + scale)))

    if(rounded < 0 and q != 0, do: "-", else: "") <> render(q, scale)
  end

  defp shortest(x) do
    %{"int" => int, "frac" => frac, "exp" => exp} =
      Regex.named_captures(
        ~r/\A(?<int>\d+)\.(?<frac>\d+)(?:e(?<exp>[+-]?\d+))?\z/,
        :erlang.float_to_binary(abs(x), [:short])
      )

    {String.to_integer(int <> frac),
     if(exp == "", do: 0, else: String.to_integer(exp)) - byte_size(frac)}
  end

  defp significant(0, _exp10, _precision), do: {0, 0}

  defp significant(digits, exp10, precision) do
    drop = length(Integer.digits(digits)) - precision

    if drop <= 0 do
      {digits, exp10}
    else
      m = half_even(digits, Integer.pow(10, drop))

      if m == Integer.pow(10, precision),
        do: {div(m, 10), exp10 + drop + 1},
        else: {m, exp10 + drop}
    end
  end

  defp half_even(a, b) do
    {q, r} = {div(a, b), rem(a, b)}
    if 2 * r > b or (2 * r == b and rem(q, 2) == 1), do: q + 1, else: q
  end

  defp half_up(a, b), do: if(2 * rem(a, b) >= b, do: div(a, b) + 1, else: div(a, b))

  defp render(q, 0), do: Integer.to_string(q)

  defp render(q, digits) do
    scale = Integer.pow(10, digits)
    "#{div(q, scale)}.#{String.pad_leading(Integer.to_string(rem(q, scale)), digits, "0")}"
  end
end
