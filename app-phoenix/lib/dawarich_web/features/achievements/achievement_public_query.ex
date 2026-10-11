defmodule DawarichWeb.AchievementPublicQuery do
  @moduledoc false
  alias Dawarich.Auth.Admission

  def decode(raw, fields) do
    if byte_size(raw) > 65_536, do: throw(:parameters)
    pairs = String.split(raw, ~r/& */, trim: true)

    Enum.reduce(pairs, %{}, fn pair, params ->
      [key | value] = String.split(pair, "=", parts: 2)
      value = if value == [], do: nil, else: component(hd(value))
      store(params, component(key), value, 0) || params
    end)

    query =
      pairs
      |> Enum.filter(fn pair ->
        key = pair |> String.split("=", parts: 2) |> hd() |> component()
        Enum.any?(fields, &(key == &1 or String.starts_with?(key, &1 <> "[")))
      end)
      |> Enum.join("&")

    Admission.form(query, "", fields)
  rescue
    _ -> {:handoff, :parameters}
  catch
    :parameters -> {:handoff, :parameters}
  end

  def page_conn(%{method: method, request_path: path} = conn) do
    if method in ~w(GET HEAD) and path =~ ~r|\A/shared/achievements/[^/.]{1,100}\z| do
      case decode(conn.query_string, ~w(locale embed format)) do
        {:ok, params} -> %{conn | query_string: URI.encode_query(params)}
        _ -> conn
      end
    else
      conn
    end
  end

  defp component(text) do
    if text =~ ~r/%(?![0-9a-fA-F]{2})/, do: throw(:parameters)
    value = URI.decode_www_form(text)
    if String.valid?(value), do: value, else: throw(:parameters)
  end

  defp store(_params, _name, _value, depth) when depth >= 100, do: throw(:parameters)

  defp store(params, name, value, depth) do
    {key, after_key} = split_name(name, depth)

    cond do
      key == "" ->
        nil

      after_key == "" ->
        if key == "[]" and depth != 0,
          do: if(is_nil(value), do: [], else: [value]),
          else: Map.put(params, key, value)

      after_key == "[" ->
        Map.put(params, name, value)

      after_key == "[]" ->
        list = container(params, key, :array)
        Map.put(params, key, if(is_nil(value), do: list, else: list ++ [value]))

      String.starts_with?(after_key, "[]") ->
        child = binary_part(after_key, 2, byte_size(after_key) - 2)

        child =
          case Regex.run(~r/\A\[([^\[\]]+)\]\z/, child) do
            [_, key] -> key
            _ -> child
          end

        list = container(params, key, :array)
        last = List.last(list)

        list =
          if is_map(last) and not has_key?(last, child),
            do: List.replace_at(list, -1, store(last, child, value, depth + 1)),
            else: list ++ [store(%{}, child, value, depth + 1)]

        Map.put(params, key, list)

      true ->
        map = container(params, key, :hash)
        Map.put(params, key, store(map, after_key, value, depth + 1))
    end
  end

  defp split_name(name, 0) do
    case :binary.match(name, "[", scope: {min(1, byte_size(name)), max(0, byte_size(name) - 1)}) do
      {start, _} ->
        {binary_part(name, 0, start), binary_part(name, start, byte_size(name) - start)}

      :nomatch ->
        {name, ""}
    end
  end

  defp split_name("[]" <> rest, _depth), do: {"[]", rest}

  defp split_name("[" <> rest = name, _depth) do
    case String.split(rest, "]", parts: 2) do
      [key, after_key] -> {key, after_key}
      _ -> {name, ""}
    end
  end

  defp split_name(name, _depth), do: {name, ""}

  defp container(params, key, type) do
    value = Map.get(params, key) || if(type == :array, do: [], else: %{})

    if (type == :array and is_list(value)) or (type == :hash and is_map(value)),
      do: value,
      else: throw(:parameters)
  end

  defp has_key?(params, key) do
    if String.contains?(key, "[]") do
      false
    else
      key
      |> String.split(~r/[\[\]]+/, trim: true)
      |> Enum.reduce_while(params, fn part, map ->
        if is_map(map) and Map.has_key?(map, part),
          do: {:cont, map[part]},
          else: {:halt, :missing}
      end)
      |> then(&(&1 != :missing))
    end
  end
end
