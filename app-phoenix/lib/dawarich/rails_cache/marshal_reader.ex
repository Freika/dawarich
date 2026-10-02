defmodule Dawarich.RailsCache.MarshalReader do
  @moduledoc false
  import Bitwise
  alias Dawarich.RailsCache.Value

  def decode(<<4, 8, bytes::binary>>) do
    {value, <<>>, _} = read(bytes, %{symbols: [], objects: []})
    {:ok, value}
  rescue
    _ -> {:error, :invalid_marshal}
  catch
    reason -> {:error, reason}
  end

  def decode(_), do: {:error, :invalid_marshal_header}

  defp read(<<tag, rest::binary>>, state) when tag in [?0, ?T, ?F],
    do: {Map.fetch!(%{?0 => nil, ?T => true, ?F => false}, tag), rest, state}

  defp read(<<?i, rest::binary>>, state) do
    {n, rest} = long(rest)
    {n, rest, state}
  end

  defp read(<<?:, rest::binary>>, state) do
    {name, rest} = bytes(rest)
    value = {:ruby_symbol, name}
    {value, rest, %{state | symbols: state.symbols ++ [value]}}
  end

  defp read(<<?;, rest::binary>>, state) do
    {index, rest} = long(rest)
    {Enum.fetch!(state.symbols, index), rest, state}
  end

  defp read(<<?@, rest::binary>>, state) do
    {index, rest} = long(rest)

    case Enum.fetch!(state.objects, index) do
      :reserved -> throw(:cyclic_marshal_reference)
      value -> {value, rest, state}
    end
  end

  defp read(<<?I, rest::binary>>, state) do
    before = length(state.objects)
    {value, rest, state} = read(rest, state)
    {ivars, rest, state} = pairs(rest, state)

    value =
      case {value, ivars} do
        {string, [{{:ruby_symbol, "E"}, true}]} when is_binary(string) -> string
        {%Value{} = value, ivars} -> %{value | ivars: ivars}
        {value, ivars} -> %Value{tag: :ivar, value: value, ivars: ivars}
      end

    state = if length(state.objects) > before, do: put_object(state, before, value), else: state
    {value, rest, state}
  end

  defp read(<<tag, rest::binary>>, state) when tag in [?", ?f, ?l, ?/, ?c, ?m, ?M] do
    {value, rest} = scalar(tag, rest)
    {value, rest, add_object(state, value)}
  end

  defp read(<<?[, rest::binary>>, state) do
    {size, rest} = long(rest)
    {index, state} = reserve(state)
    {items, rest, state} = many(size, rest, state)
    {items, rest, put_object(state, index, items)}
  end

  defp read(<<tag, rest::binary>>, state) when tag in [?{, ?}] do
    {index, state} = reserve(state)
    {items, rest, state} = pairs(rest, state)

    if tag == ?} do
      {default, rest, state} = read(rest, state)
      value = %Value{tag: :hash_default, value: {items, default}}
      {value, rest, put_object(state, index, value)}
    else
      value = Map.new(items)
      {value, rest, put_object(state, index, value)}
    end
  end

  defp read(<<tag, rest::binary>>, state) when tag in [?o, ?S, ?u, ?U, ?C, ?e] do
    {class, rest, state} = read(rest, state)
    {:ruby_symbol, class} = class
    {index, state} = if tag in [?C, ?e], do: {nil, state}, else: reserve(state)

    {value, rest, state} =
      cond do
        tag in [?o, ?S] ->
          pairs(rest, state)

        tag == ?u ->
          {value, rest} = bytes(rest)
          {value, rest, state}

        true ->
          read(rest, state)
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

  defp read(<<tag, _::binary>>, _state), do: throw({:unknown_marshal_tag, tag})

  defp scalar(?", rest), do: bytes(rest)

  defp scalar(?f, rest) do
    {value, rest} = bytes(rest)

    number =
      case value do
        "nan" ->
          %Value{tag: :float, value: "nan"}

        "inf" ->
          %Value{tag: :float, value: "inf"}

        "-inf" ->
          %Value{tag: :float, value: "-inf"}

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

  defp many(0, rest, state), do: {[], rest, state}

  defp many(n, rest, state) when n > 0 do
    {value, rest, state} = read(rest, state)
    {values, rest, state} = many(n - 1, rest, state)
    {[value | values], rest, state}
  end

  defp pairs(rest, state) do
    {count, rest} = long(rest)
    {items, rest, state} = many(count * 2, rest, state)
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

  defp reserve(state), do: {length(state.objects), add_object(state, :reserved)}
  defp add_object(state, value), do: %{state | objects: state.objects ++ [value]}

  defp put_object(state, index, value),
    do: %{state | objects: List.replace_at(state.objects, index, value)}
end
