defmodule Dawarich.Imports.Geometry.Wkb do
  @moduledoc false
  import Bitwise

  def unhex(text), do: text |> :binary.bin_to_list() |> Enum.map(&nibble/1) |> pack([])

  def parse(bytes) do
    case object(bytes, :top, nil) do
      {:ok, {:point, x, y}, <<>>} -> {:point, x, y}
      {:ok, _geometry, <<>>} -> {:other, bytes |> without_srid() |> Base.encode16()}
      _ -> :error
    end
  end

  defp nibble(c) when c in ?a..?z or c in ?A..?Z, do: (c &&& 15) + 9 &&& 15
  defp nibble(c), do: c &&& 15

  defp pack([high, low | rest], acc), do: pack(rest, [high * 16 + low | acc])
  defp pack([high], acc), do: pack([], [high * 16 | acc])
  defp pack([], acc), do: acc |> Enum.reverse() |> :erlang.list_to_binary()

  defp object(<<order, rest::binary>>, contained, top) when order in [0, 1] do
    endian = if order == 1, do: :little, else: :big

    with {:ok, code, rest} <- uint(rest, endian),
         {:ok, srid, rest} <- srid(code, rest, endian),
         type = code &&& 0x0FFFFFFF,
         true <- (code &&& 0xC0000000) == 0,
         true <- contained in [:top, :any] or contained == type,
         true <- contained == :top or srid in [nil, top] do
      body(type, rest, endian, if(contained == :top, do: srid || 4326, else: top))
    else
      _ -> :error
    end
  end

  defp object(_bytes, _contained, _top), do: :error

  defp srid(code, rest, endian) when (code &&& 0x20000000) != 0, do: uint(rest, endian)
  defp srid(_code, rest, _endian), do: {:ok, nil, rest}

  defp body(1, rest, endian, _top) do
    with {:ok, x, rest} <- coordinate(rest, endian),
         {:ok, y, rest} <- coordinate(rest, endian),
         do: {:ok, {:point, x, y}, rest}
  end

  defp body(2, rest, endian, _top), do: line(rest, endian)

  defp body(3, rest, endian, _top) do
    with {:ok, count, rest} <- uint(rest, endian),
         do: repeat(count, rest, &line(&1, endian))
  end

  defp body(type, rest, endian, top) when type in 4..7 do
    contained = if type == 7, do: :any, else: type - 3

    with {:ok, count, rest} <- uint(rest, endian),
         do: repeat(count, rest, &object(&1, contained, top))
  end

  defp body(_type, _rest, _endian, _top), do: :error

  defp line(rest, endian) do
    with {:ok, count, rest} <- uint(rest, endian),
         true <- byte_size(rest) >= count * 16,
         <<_::binary-size(^count * 16), rest::binary>> <- rest,
         do: {:ok, :other, rest},
         else: (_ -> :error)
  end

  defp repeat(0, rest, _fun), do: {:ok, :other, rest}

  defp repeat(count, rest, fun) do
    case fun.(rest) do
      {:ok, _geometry, rest} -> repeat(count - 1, rest, fun)
      :error -> :error
    end
  end

  defp uint(<<value::little-32, rest::binary>>, :little), do: {:ok, value, rest}
  defp uint(<<value::big-32, rest::binary>>, :big), do: {:ok, value, rest}
  defp uint(_bytes, _endian), do: :error

  defp coordinate(<<bits::little-64, rest::binary>>, :little), do: {:ok, float(bits), rest}
  defp coordinate(<<bits::big-64, rest::binary>>, :big), do: {:ok, float(bits), rest}
  defp coordinate(_bytes, _endian), do: :error

  defp float(bits) when (bits >>> 52 &&& 0x7FF) == 0x7FF do
    cond do
      (bits &&& 0xFFFFFFFFFFFFF) != 0 -> :nan
      bits >>> 63 == 1 -> :neg_infinity
      true -> :infinity
    end
  end

  defp float(bits) do
    <<value::float-64>> = <<bits::64>>
    value
  end

  defp without_srid(<<1, code::little-32, _srid::32, rest::binary>>)
       when (code &&& 0x20000000) != 0,
       do: <<1, code &&& bnot(0x20000000)::little-32, rest::binary>>

  defp without_srid(<<0, code::big-32, _srid::32, rest::binary>>)
       when (code &&& 0x20000000) != 0,
       do: <<0, code &&& bnot(0x20000000)::big-32, rest::binary>>

  defp without_srid(bytes), do: bytes
end
