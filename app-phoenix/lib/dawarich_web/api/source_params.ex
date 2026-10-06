defmodule DawarichWeb.Api.SourceParams do
  @moduledoc false

  def decode(text) do
    entries = String.split(text, "&", trim: true)

    if length(entries) > 4096 or byte_size(text) > 4_194_304, do: throw(:bad_request)

    params =
      Enum.reduce(entries, %{}, fn entry, params ->
        [key | value] = String.split(entry, "=", parts: 2)
        key = component(key)
        value = if value == [], do: nil, else: component(hd(value))
        if key == "", do: params, else: insert(params, keys(key), value)
      end)

    {:ok, munge(params)}
  rescue
    _ -> {:error, 400}
  catch
    :bad_request -> {:error, 400}
  end

  def munge(%Jason.OrderedObject{values: pairs}),
    do: Map.new(pairs, fn {key, value} -> {key, munge(value)} end)

  def munge(%Plug.Upload{} = file), do: file
  def munge(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, munge(value)} end)
  def munge(list) when is_list(list), do: for(value <- list, value != nil, do: munge(value))
  def munge(value), do: value

  defp component(text) do
    if text =~ ~r/%(?![0-9a-fA-F]{2})/, do: throw(:bad_request)
    value = URI.decode_www_form(text)
    if String.valid?(value), do: value, else: throw(:bad_request)
  end

  defp keys(key) do
    [root | tail] = String.split(key, "[", parts: 2)

    case tail do
      [] ->
        [root]

      [rest] ->
        parts = Regex.scan(~r/\[([^\[\]]*)\]/, "[" <> rest)

        if Enum.map_join(parts, &hd/1) != "[" <> rest or length(parts) >= 32,
          do: throw(:bad_request)

        [root | Enum.map(parts, fn [_, name] -> if name == "", do: :array, else: name end)]
    end
  end

  defp insert(map, [key], value) when is_map(map), do: Map.put(map, key, value)

  defp insert(map, [key | rest], value) when is_map(map) do
    empty = if hd(rest) == :array, do: [], else: %{}
    previous = Map.get(map, key, empty)
    Map.put(map, key, insert(previous, rest, value))
  end

  defp insert(list, [:array], value) when is_list(list), do: list ++ [value]

  defp insert(list, [:array | rest], value) when is_list(list) do
    case List.last(list) do
      %{} = last ->
        if available?(last, rest),
          do: List.replace_at(list, -1, insert(last, rest, value)),
          else: list ++ [insert(%{}, rest, value)]

      _ ->
        list ++ [insert(if(hd(rest) == :array, do: [], else: %{}), rest, value)]
    end
  end

  defp insert(_container, _keys, _value), do: throw(:bad_request)

  defp available?(map, [key]), do: not Map.has_key?(map, key)

  defp available?(map, [key | rest]) when is_map(map),
    do: not Map.has_key?(map, key) or available?(map[key], rest)

  defp available?(_map, _keys), do: false
end
