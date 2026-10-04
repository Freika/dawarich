defmodule Dawarich.Imports.XmlAmpersands do
  @moduledoc false
  alias Dawarich.Imports.XmlInput
  @entities ~w(amp lt gt quot apos)

  def copy(source, target) do
    File.open!(source, [:read, :binary, :raw], fn input ->
      File.open!(target, [:write, :binary, :raw], fn output ->
        copy(XmlInput.new(input, streamed_text: true), output, "", false)
      end)
    end)
  end

  defp copy(input, output, pending, cdata) do
    case XmlInput.next(input) do
      {"", _} ->
        IO.binwrite(output, escape(pending, cdata, true) |> elem(0))

      {bytes, input} ->
        {text, pending, cdata} = escape(pending <> bytes, cdata, false)

        if byte_size(pending) > 1_048_576,
          do: raise(ArgumentError, "XML entity token exceeds limit")

        IO.binwrite(output, text)
        copy(input, output, pending, cdata)
    end
  end

  defp escape(bytes, cdata, final), do: scan(bytes, cdata, final, [])
  defp scan("", cdata, _, acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), "", cdata}

  defp scan(<<"<![CDATA[", rest::binary>>, false, final, acc),
    do: scan(rest, true, final, ["<![CDATA[" | acc])

  defp scan(<<"]]>", rest::binary>>, true, final, acc),
    do: scan(rest, false, final, ["]]>" | acc])

  defp scan(<<"&", rest::binary>> = bytes, false, final, acc) do
    case Regex.run(~r/\A([a-zA-Z][a-zA-Z0-9]*|#\d+|#x[0-9a-fA-F]+);/, rest) do
      [full, entity] ->
        prefix = if legal?(entity), do: "&", else: "&amp;"

        scan(
          binary_part(rest, byte_size(full), byte_size(rest) - byte_size(full)),
          false,
          final,
          [prefix <> full | acc]
        )

      nil ->
        if not final and Regex.match?(~r/\A[a-zA-Z0-9#]*\z/, rest),
          do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), bytes, false},
          else: scan(rest, false, final, ["&amp;" | acc])
    end
  end

  defp scan(bytes, cdata, false, acc) when byte_size(bytes) < 9 do
    if String.starts_with?("<![CDATA[", bytes) or (cdata and String.starts_with?("]]>", bytes)),
      do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), bytes, cdata},
      else: scan_byte(bytes, cdata, false, acc)
  end

  defp scan(bytes, cdata, final, acc), do: scan_byte(bytes, cdata, final, acc)

  defp scan_byte(<<byte, rest::binary>>, cdata, final, acc),
    do: scan(rest, cdata, final, [<<byte>> | acc])

  defp legal?("#x" <> n), do: legal_codepoint?(String.to_integer(n, 16))
  defp legal?("#" <> n), do: legal_codepoint?(String.to_integer(n))
  defp legal?(name), do: name in @entities

  defp legal_codepoint?(n),
    do: n in [9, 10, 13] or n in 32..0xD7FF or n in 0xE000..0xFFFD or n in 0x10000..0x10FFFF
end
