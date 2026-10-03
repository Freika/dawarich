defmodule Dawarich.Imports.DateCompact do
  @moduledoc false
  alias Dawarich.Imports.DateOffsets

  @pattern ~r/([-+]?)(?<!\d)(\d{2,14})(?:\s*t?\s*(\d{2,6})?(?:[,.](\d*))?)?(?:\s*(z\b|[-+]\d{1,4}\b|\[[-+]?\d[^\]]*\]))?/i

  def parse(text) do
    case Regex.run(@pattern, text) do
      nil ->
        nil

      [whole | groups] ->
        [sign, digits, clock, fraction, zone] = groups ++ List.duplicate("", 5 - length(groups))
        {fraction_start, _length} = Enum.at(Regex.run(@pattern, text, return: :index), 4, {-1, 0})
        fractional? = fraction_start >= 0
        fields = first(digits, sign, fractional? && clock == "")
        fields = second(fields, clock, fractional?)

        fields =
          if fractional?, do: Map.put(fields, "sec_fraction", rational(fraction)), else: fields

        fields = zone(fields, zone)
        {String.replace(text, whole, " ", global: false), fields}
    end
  end

  defp first(digits, sign, reverse?) do
    n = byte_size(digits)

    specs =
      cond do
        reverse? && n in [2, 3, 4, 5, 6, 7, 8, 10, 12, 14] ->
          reverse(n)

        n == 2 ->
          [{"mday", 0, 2}]

        n == 3 ->
          [{"yday", 0, 3}]

        n == 4 ->
          [{"mon", 0, 2}, {"mday", 2, 2}]

        n == 5 ->
          [{"year", 0, 2}, {"yday", 2, 3}]

        n == 6 ->
          [{"year", 0, 2}, {"mon", 2, 2}, {"mday", 4, 2}]

        n == 7 ->
          [{"year", 0, 4}, {"yday", 4, 3}]

        n in [8, 10, 12, 14] ->
          Enum.take(
            [
              {"year", 0, 4},
              {"mon", 4, 2},
              {"mday", 6, 2},
              {"hour", 8, 2},
              {"min", 10, 2},
              {"sec", 12, 2}
            ],
            3 + div(n - 8, 2)
          )

        true ->
          []
      end

    fields(digits, specs)
    |> Map.update("year", nil, &if(sign == "-", do: -&1, else: &1))
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp reverse(n) do
    [{"sec", n - 2, 2}] ++
      if(n >= 3, do: [{"min", max(0, n - 4), min(2, n - 2)}], else: []) ++
      if(n >= 5, do: [{"hour", max(0, n - 6), min(2, n - 4)}], else: []) ++
      if(n >= 7, do: [{"mday", max(0, n - 8), min(2, n - 6)}], else: []) ++
      if(n >= 10, do: [{"mon", n - 10, 2}], else: []) ++
      if(n in [12, 14], do: [{"year", 0, n - 10}], else: [])
  end

  defp second(fields, "", _fractional?), do: fields

  defp second(fields, clock, fractional?) do
    n = byte_size(clock)

    if n in [2, 4, 6] do
      specs =
        if fractional?,
          do: reverse(n),
          else: Enum.take([{"hour", 0, 2}, {"min", 2, 2}, {"sec", 4, 2}], div(n, 2))

      Map.merge(fields, fields(clock, specs))
    else
      fields
    end
  end

  defp fields(text, specs),
    do:
      Map.new(specs, fn {key, pos, n} ->
        {key, text |> binary_part(pos, n) |> String.to_integer()}
      end)

  def rational(""), do: %{"numerator" => 0, "denominator" => 1}

  def rational(digits) do
    n = String.to_integer(digits)
    d = Integer.pow(10, byte_size(digits))
    gcd = Integer.gcd(n, d)
    %{"numerator" => div(n, gcd), "denominator" => div(d, gcd)}
  end

  defp zone(fields, ""), do: fields

  defp zone(fields, "[" <> bracket) do
    text = String.trim_trailing(bracket, "]")

    {offset, zone} =
      case String.split(text, ":", parts: 2) do
        [offset, name] -> {offset <> ":", name}
        [name] -> {if(name =~ ~r/\A\d/, do: "+" <> name, else: name), name}
      end

    fields |> Map.put("zone", zone) |> Map.put("offset", DateOffsets.parse(offset))
  end

  defp zone(fields, zone), do: Map.put(fields, "zone", zone)
end
