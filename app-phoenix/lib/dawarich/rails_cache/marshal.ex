defmodule Dawarich.RailsCache.Marshal do
  @moduledoc "Reads Ruby Marshal 4.8 data without executing Ruby or resolving class constants."
  import Bitwise
  alias Dawarich.RailsCache.Value

  @max_depth 64
  @max_entries 100_000

  def decode(bytes, opts \\ [])

  def decode(<<4, 8, bytes::binary>>, opts) do
    state = %{symbols: %{}, objects: %{}, hash: Keyword.get(opts, :hash, :map)}
    {value, <<>>, _} = read(bytes, state, 0)
    {:ok, value}
  rescue
    _ -> {:error, :invalid_marshal}
  catch
    reason -> {:error, reason}
  end

  def decode(_, _opts), do: {:error, :invalid_marshal_header}

  defp read(_bytes, _state, depth) when depth > @max_depth, do: throw(:too_deep)

  defp read(<<tag, rest::binary>>, state, _depth) when tag in [?0, ?T, ?F],
    do: {Map.fetch!(%{?0 => nil, ?T => true, ?F => false}, tag), rest, state}

  defp read(<<?i, rest::binary>>, state, _depth) do
    {n, rest} = long(rest)
    {n, rest, state}
  end

  defp read(<<?:, rest::binary>>, state, _depth) do
    {name, rest} = bytes(rest)
    value = {:ruby_symbol, name}
    {value, rest, %{state | symbols: append(state.symbols, value)}}
  end

  defp read(<<?;, rest::binary>>, state, _depth) do
    {index, rest} = long(rest)
    {Map.fetch!(state.symbols, index), rest, state}
  end

  defp read(<<?@, rest::binary>>, state, _depth) do
    {index, rest} = long(rest)

    case Map.fetch!(state.objects, index) do
      :reserved -> throw(:cyclic_marshal_reference)
      value -> {value, rest, state}
    end
  end

  defp read(<<?I, rest::binary>>, state, depth) do
    before = map_size(state.objects)
    {value, rest, state} = read(rest, state, depth + 1)
    {ivars, rest, state} = pairs(rest, state, depth + 1)

    value =
      case {value, ivars} do
        {string, [{{:ruby_symbol, "E"}, true}]} when is_binary(string) -> string
        {%Value{} = value, ivars} -> %{value | ivars: ivars}
        {value, ivars} -> %Value{tag: :ivar, value: value, ivars: ivars}
      end

    state = if map_size(state.objects) > before, do: put_object(state, before, value), else: state
    {value, rest, state}
  end

  defp read(<<tag, rest::binary>>, state, _depth) when tag in [?", ?f, ?l, ?/, ?c, ?m, ?M] do
    {value, rest} = scalar(tag, rest)
    {value, rest, %{state | objects: append(state.objects, value)}}
  end

  defp read(<<?[, rest::binary>>, state, depth) do
    {size, rest} = long(rest)
    {index, state} = reserve(state)
    {items, rest, state} = many(size, rest, state, depth + 1)
    {items, rest, put_object(state, index, items)}
  end

  defp read(<<tag, rest::binary>>, state, depth) when tag in [?{, ?}] do
    {index, state} = reserve(state)
    {items, rest, state} = pairs(rest, state, depth + 1)

    {default, rest, state} =
      if tag == ?}, do: read(rest, state, depth + 1), else: {nil, rest, state}

    value =
      if tag == ?{ and state.hash == :map,
        do: Map.new(items),
        else: %Value{tag: :hash_default, value: {items, default}}

    {value, rest, put_object(state, index, value)}
  end

  defp read(<<tag, rest::binary>>, state, depth) when tag in [?o, ?S, ?u, ?U, ?C, ?e] do
    {{:ruby_symbol, class}, rest, state} = read(rest, state, depth + 1)
    {index, state} = if tag in [?C, ?e], do: {nil, state}, else: reserve(state)

    {value, rest, state} =
      cond do
        tag in [?o, ?S] ->
          pairs(rest, state, depth + 1)

        tag == ?u ->
          {value, rest} = bytes(rest)
          {value, rest, state}

        true ->
          read(rest, state, depth + 1)
      end

    kind =
      %{
        ?o => :object,
        ?S => :struct,
        ?u => :user_defined,
        ?U => :user_marshal,
        ?C => :user_class,
        ?e => :extended
      }[tag]

    value = %Value{tag: kind, class: class, value: value}
    state = if index, do: put_object(state, index, value), else: state
    {value, rest, state}
  end

  defp read(<<tag, _::binary>>, _state, _depth), do: throw({:unknown_marshal_tag, tag})

  defp scalar(?", rest), do: bytes(rest)

  defp scalar(?f, rest) do
    {value, rest} = bytes(rest)

    number =
      case value do
        special when special in ["nan", "inf", "-inf"] ->
          %Value{tag: :float, value: special}

        _ ->
          case Float.parse(value) do
            {n, _} -> n
            :error -> String.to_integer(value) * 1.0
          end
      end

    {number, rest}
  end

  defp scalar(?l, <<sign, rest::binary>>) do
    {words, rest} = long(rest)
    <<digits::binary-size(words * 2), rest::binary>> = rest
    value = :binary.decode_unsigned(digits, :little)
    {if(sign == ?-, do: -value, else: value), rest}
  end

  defp scalar(?/, rest) do
    {pattern, <<flags, rest::binary>>} = bytes(rest)
    {%Value{tag: :regexp, value: {pattern, flags}}, rest}
  end

  defp scalar(tag, rest) do
    {name, rest} = bytes(rest)
    kind = %{?c => :class, ?m => :module, ?M => :module_old}[tag]
    {%Value{tag: kind, value: name}, rest}
  end

  defp many(n, rest, state, depth, acc \\ [])
  defp many(0, rest, state, _depth, acc), do: {Enum.reverse(acc), rest, state}

  defp many(n, rest, state, depth, acc) when n > 0 do
    {value, rest, state} = read(rest, state, depth)
    many(n - 1, rest, state, depth, [value | acc])
  end

  defp pairs(rest, state, depth) do
    {count, rest} = long(rest)
    {items, rest, state} = many(count * 2, rest, state, depth)
    {Enum.map(Enum.chunk_every(items, 2), fn [k, v] -> {k, v} end), rest, state}
  end

  defp bytes(rest) do
    {size, rest} = long(rest)
    <<value::binary-size(size), rest::binary>> = rest
    {value, rest}
  end

  defp long(<<byte::signed-8, rest::binary>>) do
    cond do
      byte == 0 ->
        {0, rest}

      byte > 4 ->
        {byte - 5, rest}

      byte < -4 ->
        {byte + 5, rest}

      byte > 0 ->
        <<value::little-unsigned-size(byte * 8), rest::binary>> = rest
        {value, rest}

      true ->
        n = -byte
        <<value::little-unsigned-size(n * 8), rest::binary>> = rest
        {value - (1 <<< (n * 8)), rest}
    end
  end

  defp append(table, _value) when map_size(table) >= @max_entries, do: throw(:too_large)
  defp append(table, value), do: Map.put(table, map_size(table), value)

  defp reserve(state),
    do: {map_size(state.objects), %{state | objects: append(state.objects, :reserved)}}

  defp put_object(state, index, value),
    do: %{state | objects: Map.put(state.objects, index, value)}
end
