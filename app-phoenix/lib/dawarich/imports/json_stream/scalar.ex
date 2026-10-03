defmodule Dawarich.Imports.JsonStream.Scalar do
  @moduledoc false
  import Bitwise
  alias Dawarich.Imports.JsonStream.Reader
  @named %{?b => <<8>>, ?f => <<12>>, ?n => <<10>>, ?r => <<13>>, ?t => <<9>>}

  def read(?", r, keep, opts), do: string(r, keep, Keyword.get(opts, :unicode, :saj))

  def read(c, r, keep, _opts) when c in [?n, ?t, ?f] do
    {token, value} = %{?n => {"ull", nil}, ?t => {"rue", true}, ?f => {"alse", false}}[c]
    r = Enum.reduce(:binary.bin_to_list(token), r, &Reader.expect(&2, &1))
    {if(keep, do: value, else: nil), r}
  end

  def read(?I, r, keep, _opts), do: infinity(r, keep, :infinity)

  def read(?N, r, keep, opts) do
    if not Keyword.get(opts, :allow_nan, false), do: throw(:invalid)
    r = r |> Reader.expect(?a) |> Reader.expect(?N)
    {if(keep, do: :nan, else: nil), r}
  end

  def read(c, r, keep, opts) when c in [?+, ?-] or c in ?0..?9 do
    strict = Keyword.get(opts, :strict_numbers, false)
    decoder = Keyword.get(opts, :number_decoder)
    if c == ?+ and strict, do: throw(:invalid)

    case Reader.peek(r) do
      {?I, r} when c in [?+, ?-] ->
        infinity(Reader.expect(r, ?I), keep, if(c == ?-, do: :neg_infinity, else: :infinity))

      {_, r} when strict ->
        strict_number(r, c, keep, decoder)

      {_, r} ->
        state = if(c in [?+, ?-], do: :sign, else: if(c == ?0, do: :zero, else: :int))
        number(r, if(keep, do: <<c>>, else: ""), keep, state, decoder)
    end
  end

  def read(_, _, _, _), do: throw(:invalid)

  defp infinity(r, keep, value) do
    r = Enum.reduce(~c"nfinity", r, &Reader.expect(&2, &1))
    {if(keep, do: value, else: nil), r}
  end

  def string(r, mode, unicode), do: chars(r, mode, unicode, [], 0)

  defp chars(r, mode, unicode, acc, size) do
    {piece, r} = Reader.chunk(r)
    acc = save(acc, piece, mode, size)
    size = size + byte_size(piece)

    case Reader.peek(r) do
      {?", r} ->
        {finish(acc, mode, size, unicode), Reader.expect(r, ?")}

      {?\\, r} ->
        {piece, raw, r} = r |> Reader.expect(?\\) |> escape(unicode)
        chars(r, mode, unicode, save(acc, piece, mode, size), size + raw)

      {0, _r} when unicode in [:phone_validate, :phone_saj] ->
        raise ArgumentError, "string contains null byte"

      {c, r} when is_integer(c) and c != 0 ->
        chars(r, mode, unicode, acc, size)

      _ ->
        throw(:invalid)
    end
  end

  defp save(acc, _piece, false, _size), do: acc
  defp save(acc, _piece, :key, size) when size > 256, do: acc
  defp save(acc, piece, _mode, _size), do: [acc, piece]

  defp finish(_acc, false, _size, _unicode), do: nil
  defp finish(_acc, :key, size, _unicode) when size > 256, do: nil

  defp finish(acc, _mode, _size, unicode) do
    text = acc |> IO.iodata_to_binary() |> scrub()
    if unicode == :phone_saj, do: text |> :binary.split(<<0>>) |> hd(), else: text
  end

  defp escape(r, unicode) do
    case Reader.get(r) do
      {c, r} when c in [?", ?\\, ?/] -> {<<c>>, 2, r}
      {c, r} when is_map_key(@named, c) -> {@named[c], 2, r}
      {?u, r} -> unicode_escape(r, unicode)
      {c, r} when unicode == :json and is_integer(c) -> {<<c>>, 2, r}
      _ -> throw(:invalid)
    end
  end

  defp unicode_escape(r, unicode) do
    {code, r} = hex(r)

    cond do
      unicode in [:saj, :phone_validate] ->
        {cesu(code), 6, r}

      code in 0xD800..0xDBFF ->
        {low, r} = r |> Reader.expect(?\\) |> Reader.expect(?u) |> hex()
        if low not in 0xDC00..0xDFFF, do: throw(:invalid)
        {<<0x10000 + ((code - 0xD800) <<< 10) + (low - 0xDC00)::utf8>>, 12, r}

      code in 0xDC00..0xDFFF ->
        throw(:invalid)

      true ->
        {<<code::utf8>>, 6, r}
    end
  end

  defp cesu(code) when code < 128, do: <<code>>
  defp cesu(code) when code < 2048, do: <<192 + div(code, 64), 128 + rem(code, 64)>>

  defp cesu(code),
    do: <<224 + div(code, 4096), 128 + rem(div(code, 64), 64), 128 + rem(code, 64)>>

  defp hex(r) do
    Enum.reduce(1..4, {0, r}, fn _, {code, r} ->
      case Reader.get(r) do
        {c, r} when c in ?0..?9 -> {code * 16 + c - ?0, r}
        {c, r} when c in ?A..?F -> {code * 16 + c - ?A + 10, r}
        {c, r} when c in ?a..?f -> {code * 16 + c - ?a + 10, r}
        _ -> throw(:invalid)
      end
    end)
  end

  defp strict_number(r, c, keep, decoder) do
    {sign, digits} = if c == ?-, do: {"-", ""}, else: {"", <<c>>}
    {digits, r} = take_digits(r, digits)
    if Regex.match?(~r/\A0+[1-9]/, digits), do: throw(:invalid)
    {fraction, r} = strict_fraction(r, digits)
    {exponent, r} = strict_exponent(r)
    text = sign <> digits <> fraction <> exponent

    value =
      cond do
        not keep ->
          nil

        decoder ->
          decoder.(text)

        true ->
          decode_number(sign <> if(digits == "", do: "0", else: digits) <> fraction <> exponent)
      end

    {value, r}
  end

  defp strict_fraction(r, digits) do
    case Reader.peek(r) do
      {?., r} ->
        if digits == "", do: throw(:invalid)
        r = Reader.expect(r, ?.)

        case Reader.peek(r) do
          {d, r} when d in ?0..?9 -> take_digits(r, ".")
          _ -> throw(:invalid)
        end

      {_, r} ->
        {"", r}
    end
  end

  defp strict_exponent(r) do
    case Reader.peek(r) do
      {e, r} when e in [?e, ?E] ->
        r = Reader.expect(r, e)

        {sign, r} =
          case Reader.peek(r) do
            {s, r} when s in [?+, ?-] -> {<<s>>, Reader.expect(r, s)}
            {_, r} -> {"", r}
          end

        {digits, r} = take_digits(r, "")
        if digits == "", do: throw(:invalid_float)
        {<<e>> <> sign <> digits, r}

      {_, r} ->
        {"", r}
    end
  end

  defp take_digits(r, acc) do
    case Reader.peek(r) do
      {d, r} when d in ?0..?9 -> take_digits(Reader.expect(r, d), acc <> <<d>>)
      {_, r} -> {acc, r}
    end
  end

  defp number(r, bytes, keep, state, decoder) do
    {c, r} = Reader.peek(r)

    next =
      cond do
        c in ?0..?9 and state in [:sign, :int, :zero] -> :int
        c in ?0..?9 and state in [:dot, :fraction] -> :fraction
        c in ?0..?9 and state in [:e, :esign, :exp] -> :exp
        c == ?. and state in [:sign, :int, :zero] -> :dot
        c in [?E, ?e] and state in [:int, :zero, :dot, :fraction] -> :e
        c in [?+, ?-] and state == :e -> :esign
        true -> nil
      end

    if next do
      {_, r} = Reader.get(r)
      number(r, if(keep, do: bytes <> <<c>>, else: bytes), keep, next, decoder)
    else
      value =
        cond do
          not keep -> nil
          decoder -> decoder.(bytes)
          true -> bytes |> lenient() |> decode_number()
        end

      {value, r}
    end
  end

  defp lenient(bytes) do
    %{"sign" => sign, "digits" => digits, "fraction" => fraction, "exponent" => exponent} =
      Regex.named_captures(
        ~r/\A(?<sign>[+-]?)(?<digits>\d*)(?<fraction>\.\d*)?(?<exponent>[eE][+-]?\d+)?/,
        bytes
      )

    fraction =
      if fraction in ["", "."], do: if(exponent == "", do: "", else: ".0"), else: fraction

    sign <> if(digits == "", do: "0", else: digits) <> fraction <> exponent
  end

  defp decode_number(bytes) do
    if String.contains?(bytes, [".", "e", "E"]) do
      case Float.parse(bytes) do
        {v, _rest} -> v
        :error -> if String.starts_with?(bytes, "-"), do: :neg_infinity, else: :infinity
      end
    else
      String.to_integer(bytes)
    end
  end

  defp scrub(bytes) do
    if String.valid?(bytes), do: bytes, else: bytes |> scrub(0, 0, []) |> IO.iodata_to_binary()
  end

  defp scrub(bytes, from, at, acc) do
    case bytes do
      <<_::binary-size(at)>> ->
        [acc, binary_part(bytes, from, at - from)]

      <<_::binary-size(at), cp::utf8, _::binary>> ->
        scrub(bytes, from, at + width(cp), acc)

      <<_::binary-size(at), byte, rest::binary>> ->
        skip = 1 + continuation(rest, lead_width(byte), byte)
        scrub(bytes, at + skip, at + skip, [acc, binary_part(bytes, from, at - from), "�"])
    end
  end

  defp width(cp) when cp < 0x80, do: 1
  defp width(cp) when cp < 0x800, do: 2
  defp width(cp) when cp < 0x10000, do: 3
  defp width(_cp), do: 4

  defp lead_width(byte) when byte in 0xC2..0xDF, do: 1
  defp lead_width(byte) when byte in 0xE0..0xEF, do: 2
  defp lead_width(byte) when byte in 0xF0..0xF4, do: 3
  defp lead_width(_byte), do: 0

  defp continuation(<<b, rest::binary>>, n, lead) when n > 0 and b in 0x80..0xBF do
    if (lead == 0xE0 and b < 0xA0) or (lead == 0xED and b > 0x9F) or
         (lead == 0xF0 and b < 0x90) or (lead == 0xF4 and b > 0x8F),
       do: 0,
       else: 1 + continuation(rest, n - 1, 0)
  end

  defp continuation(_rest, _n, _lead), do: 0
end
