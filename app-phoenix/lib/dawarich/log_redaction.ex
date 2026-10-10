defmodule Dawarich.LogRedaction do
  @moduledoc false

  @filtered "[FILTERED]"
  @depth 12

  def install do
    :persistent_term.put({__MODULE__, :words}, configured_words())
    :logger.add_primary_filter(__MODULE__, {&__MODULE__.filter/2, []})
  end

  def filter(event, _) do
    redact(event)
  rescue
    _ -> %{event | msg: {:string, @filtered}}
  end

  defp redact(%{msg: {:report, report}} = event), do: %{event | msg: {:report, scrub(report)}}

  defp redact(%{msg: {:string, chardata}} = event),
    do: %{event | msg: {:string, scrub_chardata(chardata)}}

  defp redact(%{msg: {format, args}} = event) when is_list(args),
    do: %{event | msg: {format, scrub(args)}}

  defp redact(event), do: event

  def scrub(term), do: scrub(term, @depth)

  defp scrub(_term, 0), do: @filtered

  defp scrub(%FunctionClauseError{} = error, _depth), do: %{error | args: nil}

  defp scrub(%{__struct__: _} = struct, depth) do
    struct
    |> Map.from_struct()
    |> Enum.reduce(struct, fn {key, value}, acc ->
      Map.put(acc, key, scrub_pair(key, value, depth))
    end)
  rescue
    _ -> @filtered
  end

  defp scrub(map, depth) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, scrub_pair(key, value, depth)} end)

  defp scrub(list, depth) when is_list(list) do
    if List.improper?(list),
      do: @filtered,
      else: Enum.map(list, &scrub(&1, depth - 1))
  end

  defp scrub(tuple, depth) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&scrub(&1, depth - 1)) |> List.to_tuple()

  defp scrub(binary, _depth) when is_binary(binary), do: scrub_binary(binary)
  defp scrub(term, _depth), do: term

  defp scrub_pair(key, value, depth),
    do: if(sensitive?(key), do: @filtered, else: scrub(value, depth - 1))

  defp scrub_chardata(chardata) do
    chardata |> IO.chardata_to_string() |> scrub_binary()
  rescue
    _ -> @filtered
  end

  defp scrub_binary(binary) do
    case words() do
      [] ->
        binary

      words ->
        if mentions?(binary, words), do: binary |> scrub_pairs() |> scrub_json(), else: binary
    end
  rescue
    _ -> @filtered
  end

  defp mentions?(binary, words), do: :binary.match(String.downcase(binary), words) != :nomatch

  defp scrub_pairs(binary) do
    Regex.replace(
      ~r/(?<![^\s&?;,"'])([^\s&=?;,"']++)=("(?:[^"\\]|\\.)*+"|[^&\s]*+)/,
      binary,
      fn whole, key, _value -> if sensitive?(key), do: key <> "=" <> @filtered, else: whole end
    )
  end

  defp scrub_json(binary) do
    Regex.replace(~r/"([^"\\]*+)"(\s*+:\s*+)"(?:[^"\\]|\\.)*+"/, binary, fn whole, key, colon ->
      if sensitive?(key), do: ~s("#{key}"#{colon}"#{@filtered}"), else: whole
    end)
  end

  defp sensitive?(key) when is_atom(key), do: sensitive?(Atom.to_string(key))

  defp sensitive?(key) when is_binary(key) do
    key = String.downcase(key)
    Enum.any?(words(), &String.contains?(key, &1))
  end

  defp sensitive?(_key), do: false

  defp words, do: :persistent_term.get({__MODULE__, :words}, nil) || configured_words()

  defp configured_words,
    do: Application.get_env(:dawarich, __MODULE__, []) |> Keyword.get(:words, []) |> List.wrap()
end
