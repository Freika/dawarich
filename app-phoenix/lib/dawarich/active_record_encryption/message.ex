defmodule Dawarich.ActiveRecordEncryption.Message do
  @moduledoc false

  @max_nesting 100
  @message_class "ActiveRecord::Encryption::Message"

  def parse(ciphertext) do
    with {:ok, data} <- decode_json(ciphertext), do: message(data, 1)
  end

  def instance(nil), do: "nil"
  def instance(true), do: "true"
  def instance(false), do: "false"
  def instance(value), do: "an instance of " <> class(value)

  def conversion(true), do: "true"
  def conversion(value), do: class(value)

  def rescued(reason), do: {:error, {:rescued, reason}}
  def raised(class, message), do: {:error, {:raised, class, message}}

  defp class(value) when is_integer(value), do: "Integer"
  defp class(value) when is_float(value), do: "Float"
  defp class(value) when is_binary(value), do: "String"
  defp class(value) when is_list(value), do: "Array"
  defp class({:object, _pairs}), do: "Hash"
  defp class({:message, _payload, _headers}), do: @message_class

  def decode_json(text) do
    with {:ok, data} <- Jason.decode(text, objects: :ordered_objects),
         {:ok, data} <- ruby_json(data, 1) do
      {:ok, data}
    else
      _ -> rescued(:invalid_json)
    end
  end

  defp ruby_json(value, depth)
       when (is_list(value) or is_struct(value, Jason.OrderedObject)) and depth > @max_nesting,
       do: :error

  defp ruby_json(%Jason.OrderedObject{values: pairs}, depth) do
    {keys, values} = Enum.unzip(pairs)

    with {:ok, values} <- ruby_json_all(values, depth + 1),
         do: {:ok, {:object, last_wins(Enum.zip(keys, values))}}
  end

  defp ruby_json(list, depth) when is_list(list), do: ruby_json_all(list, depth + 1)
  defp ruby_json(value, _depth), do: {:ok, value}

  defp ruby_json_all(items, depth) do
    items
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, done} ->
      case ruby_json(item, depth) do
        {:ok, item} -> {:cont, {:ok, [item | done]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp last_wins(pairs) do
    values = Map.new(pairs)
    pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.map(&{&1, Map.fetch!(values, &1)})
  end

  defp message(_data, level) when level > 2, do: rescued(:nesting)

  defp message({:object, pairs}, level) do
    case List.keyfind(pairs, "p", 0) do
      {"p", payload} ->
        with {:ok, payload} <- decode_if_needed(payload),
             {:ok, headers} <- properties(field(pairs, "h"), level),
             :ok <- payload_type(payload),
             {:ok, headers} <- symbolize(headers) do
          {:ok, {:message, payload, headers}}
        end

      nil ->
        rescued(:no_payload)
    end
  end

  defp message(_data, _level), do: rescued(:no_payload)

  defp field(pairs, name) do
    case List.keyfind(pairs, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp decode_if_needed(value) when is_binary(value) do
    with {:ok, decoded} <- Base.decode64(value),
         ^value <- Base.encode64(decoded) do
      {:ok, decoded}
    else
      _ -> rescued(:invalid_base64)
    end
  end

  defp decode_if_needed(value), do: {:ok, value}

  defp properties(nil, _level), do: {:ok, []}
  defp properties({:object, pairs}, level), do: collect(pairs, level)

  defp properties(list, level) when is_list(list),
    do: list |> Enum.map(&pair/1) |> collect(level)

  defp properties(other, _level),
    do: raised("NoMethodError", "undefined method 'each' for #{instance(other)}")

  defp pair(element) when is_list(element), do: {Enum.at(element, 0), Enum.at(element, 1)}
  defp pair(element), do: {element, nil}

  defp collect(pairs, level) do
    pairs
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, done} ->
      with {:ok, value} <- header_value(value, level),
           :ok <- unique(done, key) do
        {:cont, {:ok, [{key, value} | done]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      error -> error
    end
  end

  defp header_value({:object, _pairs} = value, level), do: message(value, level + 1)

  defp header_value(value, _level) do
    case decode_if_needed(value) do
      {:ok, decoded} when is_list(decoded) -> rescued(:forbidden_class)
      result -> result
    end
  end

  defp unique(done, key) do
    if Enum.any?(done, fn {seen, _value} -> seen === key end),
      do: rescued(:duplicate_header),
      else: :ok
  end

  defp payload_type(payload) when is_binary(payload) or is_nil(payload), do: :ok
  defp payload_type(_payload), do: rescued(:forbidden_class)

  defp symbolize(pairs) do
    case Enum.find(pairs, fn {key, _value} -> not is_binary(key) end) do
      nil -> {:ok, Map.new(pairs)}
      {key, _value} -> raised("NoMethodError", "undefined method 'to_sym' for #{instance(key)}")
    end
  end
end
