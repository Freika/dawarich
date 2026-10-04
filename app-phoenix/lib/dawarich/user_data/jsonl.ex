defmodule Dawarich.UserData.Jsonl do
  @moduledoc false
  alias Dawarich.Imports.JsonStream

  def reduce(path, acc, fun) do
    path
    |> File.stream!([], :line)
    |> Enum.reduce(acc, fn line, acc ->
      line = Regex.replace(~r/\A[\x00\x09-\x0D ]+|[\x00\x09-\x0D ]+\z/, line, "")
      if line == "", do: acc, else: fun.(decode!(line), acc)
    end)
  end

  def decode!(bytes) do
    JsonStream.reduce(
      {:bytes, bytes},
      nil,
      fn
        {:value, [], result, _, _}, _ -> value(result)
        _, acc -> acc
      end,
      fn _ -> true end,
      mode: :compat
    )
  end

  def value({:object, pairs}), do: Map.new(pairs, fn {key, val} -> {key, value(val)} end)
  def value(list) when is_list(list), do: Enum.map(list, &value/1)
  def value(val), do: val
end
