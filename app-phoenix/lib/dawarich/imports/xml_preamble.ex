defmodule Dawarich.Imports.XmlPreamble do
  @moduledoc false
  @limit 1_048_576
  @boms [
    {<<0, 0, 254, 255>>, {:utf32, :big}},
    {<<255, 254, 0, 0>>, {:utf32, :little}},
    {<<239, 187, 191>>, :utf8},
    {<<254, 255>>, {:utf16, :big}},
    {<<255, 254>>, {:utf16, :little}}
  ]

  def read(io) do
    prefix = read_bytes(io, 256)
    {offset, codec, locked} = physical(prefix)
    {:ok, _} = :file.position(io, offset)
    first = read_bytes(io, 64)
    raw = if declaration?(first, codec), do: declaration(io, first, codec), else: ""
    {:ok, _} = :file.position(io, offset + byte_size(raw))

    header =
      case :unicode.characters_to_binary(raw, codec, :utf8) do
        bytes when is_binary(bytes) -> bytes
        _ -> raise ArgumentError, "GPX parse error: invalid declaration encoding"
      end

    codec = if locked, do: codec, else: declared_codec(header)
    normalized = Regex.replace(~r/encoding\s*=\s*(['"])[^'"]+\1/i, header, "encoding=\"UTF-8\"")
    {codec, normalized}
  end

  defp declaration?(bytes, codec) do
    Enum.any?([" ", "\t", "\n", "\r"], fn ws ->
      String.starts_with?(bytes, encode("<?xml" <> ws, codec))
    end)
  end

  defp declaration(io, bytes, codec) do
    marker = encode("?>", codec)
    width = byte_size(encode("x", codec))

    case Enum.find(:binary.matches(bytes, marker), fn {n, _} -> rem(n, width) == 0 end) do
      {n, len} ->
        if n + len > @limit,
          do: raise(ArgumentError, "GPX parse error: declaration token exceeds limit")

        binary_part(bytes, 0, n + len)

      nil ->
        if byte_size(bytes) > @limit,
          do: raise(ArgumentError, "GPX parse error: declaration token exceeds limit")

        more = read_bytes(io, 65_536)
        if more == "", do: raise(ArgumentError, "GPX parse error: incomplete declaration")
        declaration(io, bytes <> more, codec)
    end
  end

  defp declared_codec(header) do
    case Regex.run(~r/encoding\s*=\s*['"]([^'"]+)['"]/i, header) do
      [_, name] ->
        case String.downcase(name) do
          name when name in ["iso-8859-1", "latin1"] -> :latin1
          name when name in ["utf-8", "utf8", "us-ascii", "ascii"] -> :utf8
          _ -> raise ArgumentError, "GPX parse error: unsupported or mismatched encoding"
        end

      nil ->
        :utf8
    end
  end

  defp encode(text, codec), do: :unicode.characters_to_binary(text, :utf8, codec)

  defp read_bytes(io, n) do
    case IO.binread(io, n) do
      :eof -> ""
      {:error, reason} -> raise File.Error, reason: reason, action: "read GPX", path: "input"
      bytes -> bytes
    end
  end

  defp physical(prefix) do
    case Enum.find(@boms, fn {bom, _} -> String.starts_with?(prefix, bom) end) do
      {bom, codec} ->
        {byte_size(bom), codec, true}

      nil ->
        case prefix do
          <<0, 0, 0, ?<, _::binary>> ->
            {0, {:utf32, :big}, true}

          <<?<, 0, 0, 0, _::binary>> ->
            {0, {:utf32, :little}, true}

          <<0, ?<, _::binary>> ->
            {0, {:utf16, :big}, true}

          <<?<, 0, _::binary>> ->
            {0, {:utf16, :little}, true}

          _ ->
            offset =
              case :binary.match(prefix, "<") do
                :nomatch -> 0
                {n, _} -> n
              end

            {offset, :utf8, false}
        end
    end
  end
end
