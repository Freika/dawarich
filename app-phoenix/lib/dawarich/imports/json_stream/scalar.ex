defmodule Dawarich.Imports.JsonStream.Scalar do
  @moduledoc false
  alias Dawarich.Imports.JsonStream.Reader

  def read(34, r, keep, opts), do: string(r, keep, Keyword.get(opts, :unicode, :saj))

  def read(c, r, keep, _opts) when c in [110, 116, 102] do
    {token, value} = %{110 => {"ull", nil}, 116 => {"rue", true}, 102 => {"alse", false}}[c]
    r = Enum.reduce(:binary.bin_to_list(token), r, &Reader.expect(&2, &1))
    {if(keep, do: value, else: nil), r}
  end

  def read(73, r, keep, _opts), do: infinity(r, keep, :infinity)

  def read(78, r, keep, opts) do
    if not Keyword.get(opts, :allow_nan, false), do: throw(:invalid)
    r = r |> Reader.expect(97) |> Reader.expect(78)
    {if(keep, do: :nan, else: nil), r}
  end

  def read(c, r, keep, opts) when c in [43, 45] or c in 48..57 do
    strict = Keyword.get(opts, :strict_numbers, false)
    if c == 43 and strict, do: throw(:invalid)

    case Reader.peek(r) do
      {73, r} when c in [43, 45] ->
        infinity(Reader.expect(r, 73), keep, if(c == 45, do: :neg_infinity, else: :infinity))

      {_, r} ->
        number(
          r,
          if(keep, do: <<c>>, else: ""),
          keep,
          if(c in [43, 45], do: :sign, else: if(c == 48, do: :zero, else: :int)),
          strict,
          Keyword.get(opts, :number_decoder)
        )
    end
  end

  def read(_, _, _, _), do: throw(:invalid)

  defp infinity(r, keep, value) do
    r = Enum.reduce(~c"nfinity", r, &Reader.expect(&2, &1))
    {if(keep, do: value, else: nil), r}
  end

  def string(r, mode, unicode), do: string(r, mode, [], 0, unicode)

  defp string(r, mode, acc, size, unicode) do
    case Reader.get(r) do
      {34, r} ->
        value =
          if mode == false or (mode == :key and size > 256),
            do: nil,
            else: decode_string(acc, unicode)

        {value, r}

      {92, r} ->
        {escaped, r} = escape(r, unicode)
        bytes = [92, escaped]
        string(r, mode, save(acc, bytes, mode, size), size + IO.iodata_length(bytes), unicode)

      {0, _r} when unicode in [:phone_validate, :phone_saj] ->
        raise ArgumentError, "string contains null byte"

      {c, r} when is_integer(c) and (c >= 32 or unicode in [:phone_validate, :phone_saj]) ->
        string(r, mode, save(acc, c, mode, size), size + 1, unicode)

      _ ->
        throw(:invalid)
    end
  end

  defp save(acc, _, false, _), do: acc
  defp save(acc, _, :key, size) when size > 256, do: acc
  defp save(acc, bytes, _, _), do: [bytes | acc]

  defp decode_string(acc, :phone_validate), do: decode_string(acc, :saj)

  defp decode_string(acc, :phone_saj) do
    bytes = acc |> Enum.reverse() |> IO.iodata_to_binary() |> scrub()

    bytes =
      for <<c <- bytes>>,
        into: "",
        do:
          if(c < 32,
            do: "\\u" <> String.pad_leading(Integer.to_string(c, 16), 4, "0"),
            else: <<c>>
          )

    case Jason.decode(<<34>> <> bytes <> <<34>>) do
      {:ok, value} -> value |> :binary.split(<<0>>) |> hd()
      _ -> throw(:invalid)
    end
  end

  defp decode_string(acc, :saj),
    do:
      acc
      |> Enum.reverse()
      |> IO.iodata_to_binary()
      |> saj_string([])
      |> Enum.reverse()
      |> IO.iodata_to_binary()
      |> scrub()

  defp decode_string(acc, :json) do
    bytes = [34, Enum.reverse(acc), 34] |> IO.iodata_to_binary() |> scrub()

    case Jason.decode(bytes) do
      {:ok, v} -> v
      _ -> throw(:invalid)
    end
  end

  defp saj_string(<<>>, acc), do: acc

  defp saj_string(<<92, 117, hex::binary-size(4), rest::binary>>, acc) do
    code = String.to_integer(hex, 16)

    bytes =
      cond do
        code < 128 -> <<code>>
        code < 2048 -> <<192 + div(code, 64), 128 + rem(code, 64)>>
        true -> <<224 + div(code, 4096), 128 + rem(div(code, 64), 64), 128 + rem(code, 64)>>
      end

    saj_string(rest, [bytes | acc])
  end

  defp saj_string(<<92, c, rest::binary>>, acc),
    do:
      saj_string(rest, [
        <<Map.get(%{98 => 8, 102 => 12, 110 => 10, 114 => 13, 116 => 9}, c, c)>> | acc
      ])

  defp saj_string(<<c, rest::binary>>, acc), do: saj_string(rest, [<<c>> | acc])

  defp escape(r, unicode) do
    case Reader.get(r) do
      {c, r} when c in [34, 92, 47, 98, 102, 110, 114, 116] ->
        {c, r}

      {117, r} ->
        {hex, r} = hex(r, 4, [])
        code = hex |> IO.iodata_to_binary() |> String.to_integer(16)

        cond do
          unicode in [:saj, :phone_validate] ->
            {[117, hex], r}

          code in 0xD800..0xDBFF ->
            r = r |> Reader.expect(92) |> Reader.expect(117)
            {low, r} = hex(r, 4, [])
            value = low |> IO.iodata_to_binary() |> String.to_integer(16)
            if value not in 0xDC00..0xDFFF, do: throw(:invalid)
            {[117, hex, 92, 117, low], r}

          code in 0xDC00..0xDFFF ->
            throw(:invalid)

          true ->
            {[117, hex], r}
        end

      _ ->
        throw(:invalid)
    end
  end

  defp hex(r, 0, acc), do: {Enum.reverse(acc), r}

  defp hex(r, n, acc) do
    case Reader.get(r) do
      {c, r} when c in 48..57 or c in 65..70 or c in 97..102 -> hex(r, n - 1, [c | acc])
      _ -> throw(:invalid)
    end
  end

  defp number(r, bytes, keep, state, strict, decoder) do
    {c, r} = Reader.peek(r)

    next =
      cond do
        c in 48..57 and (state in [:sign, :int] or (state == :zero and not strict)) -> :int
        c in 48..57 and state in [:dot, :fraction] -> :fraction
        c in 48..57 and state in [:e, :esign, :exp] -> :exp
        c == 46 and state in [:int, :zero] -> :dot
        c in [69, 101] and state in [:int, :zero, :fraction] -> :e
        c in [43, 45] and state == :e -> :esign
        true -> nil
      end

    if next do
      {_, r} = Reader.get(r)
      number(r, if(keep, do: bytes <> <<c>>, else: bytes), keep, next, strict, decoder)
    else
      accepted =
        if strict,
          do: [:int, :zero, :fraction, :exp],
          else: [:int, :zero, :fraction, :exp, :dot, :e, :esign]

      if strict and state in [:e, :esign], do: throw(:invalid_float)
      if state not in accepted, do: throw(:invalid)
      value = if keep, do: if(decoder, do: decoder.(bytes), else: decode_number(bytes)), else: nil
      {value, r}
    end
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

  defp scrub(bytes), do: scrub(bytes, []) |> Enum.reverse() |> IO.iodata_to_binary()
  defp scrub(<<>>, acc), do: acc
  defp scrub(<<cp::utf8, rest::binary>>, acc), do: scrub(rest, [<<cp::utf8>> | acc])

  defp scrub(<<byte, rest::binary>>, acc) do
    width =
      cond do
        byte in 0xC2..0xDF -> 1
        byte in 0xE0..0xEF -> 2
        byte in 0xF0..0xF4 -> 3
        true -> 0
      end

    scrub(prefix(rest, width, byte), ["�" | acc])
  end

  defp prefix(<<b, rest::binary>>, n, lead) when n > 0 and b in 0x80..0xBF do
    valid =
      not ((lead == 0xE0 and b < 0xA0) or (lead == 0xED and b > 0x9F) or
             (lead == 0xF0 and b < 0x90) or (lead == 0xF4 and b > 0x8F))

    if valid, do: prefix(rest, n - 1, 0), else: <<b, rest::binary>>
  end

  defp prefix(rest, _, _), do: rest
end
