defmodule DawarichWeb.Api.SourceParams do
  @moduledoc false

  def decode(text) do
    entries = String.split(text, "&", trim: true)

    if length(entries) > 4096 or byte_size(text) > 4_194_304, do: throw(:bad_request)

    pairs =
      for entry <- entries do
        [key | value] = String.split(entry, "=", parts: 2)
        {component(key), if(value == [], do: nil, else: component(hd(value)))}
      end

    {:ok, from_pairs(pairs)}
  rescue
    _ -> {:error, 400}
  catch
    :bad_request -> {:error, 400}
  end

  def from_pairs(pairs, opts \\ []) do
    ordered? = Keyword.get(opts, :ordered, false)
    empty = if ordered?, do: Jason.OrderedObject.new([]), else: %{}

    params =
      Enum.reduce(pairs, empty, fn {key, value}, params ->
        if key == "", do: params, else: insert(params, keys(key), value, ordered?)
      end)

    if ordered?, do: params, else: munge(params)
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

  defp insert(%Jason.OrderedObject{values: pairs} = object, [key | rest], value, ordered?) do
    value =
      if rest == [] do
        value
      else
        empty = if hd(rest) == :array, do: [], else: Jason.OrderedObject.new([])

        previous =
          case List.keyfind(pairs, key, 0) do
            {^key, previous} -> previous
            nil -> empty
          end

        insert(previous, rest, value, ordered?)
      end

    pairs =
      if List.keymember?(pairs, key, 0),
        do: List.keyreplace(pairs, key, 0, {key, value}),
        else: pairs ++ [{key, value}]

    %{object | values: pairs}
  end

  defp insert(map, [key], value, _ordered?) when is_map(map), do: Map.put(map, key, value)

  defp insert(map, [key | rest], value, ordered?) when is_map(map) do
    empty = if hd(rest) == :array, do: [], else: %{}
    previous = Map.get(map, key, empty)
    Map.put(map, key, insert(previous, rest, value, ordered?))
  end

  defp insert(list, [:array], value, _ordered?) when is_list(list), do: list ++ [value]

  defp insert(list, [:array | rest], value, ordered?) when is_list(list) do
    case List.last(list) do
      %{} = last ->
        if available?(last, rest),
          do: List.replace_at(list, -1, insert(last, rest, value, ordered?)),
          else: list ++ [insert(empty_map(ordered?), rest, value, ordered?)]

      _ ->
        list ++
          [
            insert(
              if(hd(rest) == :array, do: [], else: empty_map(ordered?)),
              rest,
              value,
              ordered?
            )
          ]
    end
  end

  defp insert(_container, _keys, _value, _ordered?), do: throw(:bad_request)

  defp empty_map(true), do: Jason.OrderedObject.new([])
  defp empty_map(_), do: %{}

  defp available?(%Jason.OrderedObject{values: pairs}, [key | rest]) do
    case List.keyfind(pairs, key, 0) do
      nil -> true
      {^key, value} -> rest != [] and available?(value, rest)
    end
  end

  defp available?(map, [key]), do: not Map.has_key?(map, key)

  defp available?(map, [key | rest]) when is_map(map),
    do: not Map.has_key?(map, key) or available?(map[key], rest)

  defp available?(_map, _keys), do: false
end
