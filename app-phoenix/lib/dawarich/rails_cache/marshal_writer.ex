defmodule Dawarich.RailsCache.MarshalWriter do
  @moduledoc false
  alias Dawarich.RailsCache.Value

  def encode(value), do: IO.iodata_to_binary([<<4, 8>>, dump(value)])
  defp dump(nil), do: "0"
  defp dump(true), do: "T"
  defp dump(false), do: "F"

  defp dump(n) when is_integer(n) and n >= -1_073_741_824 and n <= 1_073_741_823,
    do: ["i", long(n)]

  defp dump(n) when is_integer(n) do
    digits = :binary.encode_unsigned(abs(n), :little)
    digits = if rem(byte_size(digits), 2) == 1, do: digits <> <<0>>, else: digits
    ["l", if(n < 0, do: "-", else: "+"), long(div(byte_size(digits), 2)), digits]
  end

  defp dump(n) when is_float(n), do: ["f", bytes(:erlang.float_to_binary(n, [:short]))]

  defp dump(value) when is_binary(value),
    do: ["I", "\"", bytes(value), pairs([{{:ruby_symbol, "E"}, true}])]

  defp dump({:ruby_symbol, value}), do: [":", bytes(value)]
  defp dump(value) when is_list(value), do: ["[", long(length(value)), Enum.map(value, &dump/1)]

  defp dump(%Value{ivars: ivars} = value) when ivars != [],
    do: ["I", dump(%{value | ivars: []}), pairs(ivars)]

  defp dump(%Value{tag: :ivar, value: value}), do: dump(value)
  defp dump(%Value{tag: :raw_string, value: value}), do: ["\"", bytes(value)]
  defp dump(%Value{tag: :float, value: value}), do: ["f", bytes(value)]

  defp dump(%Value{tag: :hash_default, value: {pairs, default}}),
    do: ["}", pairs(pairs), dump(default)]

  defp dump(%Value{tag: :regexp, value: {pattern, flags}}), do: ["/", bytes(pattern), <<flags>>]

  defp dump(%Value{tag: tag, value: name}) when tag in [:class, :module, :module_old],
    do: [%{class: "c", module: "m", module_old: "M"}[tag], bytes(name)]

  defp dump(%Value{tag: tag, class: class, value: value}) do
    code =
      %{
        object: "o",
        struct: "S",
        user_defined: "u",
        user_marshal: "U",
        user_class: "C",
        extended: "e"
      }
      |> Map.fetch!(tag)

    payload =
      cond do
        tag in [:object, :struct] -> pairs(value)
        tag == :user_defined -> bytes(value)
        true -> dump(value)
      end

    [code, dump({:ruby_symbol, class}), payload]
  end

  defp dump(value) when is_map(value), do: ["{", pairs(Map.to_list(value))]

  defp pairs(items),
    do: [long(length(items)), Enum.map(items, fn {k, v} -> [dump(k), dump(v)] end)]

  defp bytes(value), do: [long(byte_size(value)), value]
  defp long(0), do: <<0>>
  defp long(n) when n > 0 and n < 123, do: <<n + 5>>
  defp long(n) when n < 0 and n > -124, do: <<n - 5::signed-8>>

  defp long(n) when n > 0 do
    digits = :binary.encode_unsigned(n, :little)
    [<<byte_size(digits)>>, digits]
  end

  defp long(n) do
    size = Enum.find(1..4, fn size -> n >= -Integer.pow(256, size) end)
    [<<-size::signed-8>>, <<n::little-signed-size(size * 8)>>]
  end
end
