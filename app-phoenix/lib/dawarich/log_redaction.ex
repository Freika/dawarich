defmodule Dawarich.LogRedaction do
  @moduledoc false

  @filtered "[FILTERED]"
  @depth 12

  def install,
    do: :logger.add_primary_filter(__MODULE__, {&__MODULE__.filter/2, []})

  def filter(%{msg: {:report, report}} = event, _), do: %{event | msg: {:report, scrub(report)}}

  def filter(%{msg: {:string, chardata}} = event, _),
    do: %{event | msg: {:string, scrub_chardata(chardata)}}

  def filter(%{msg: {format, args}} = event, _) when is_list(args),
    do: %{event | msg: {format, scrub(args)}}

  def filter(event, _), do: event

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
    if String.printable?(binary) and
         Enum.any?(words(), &String.contains?(String.downcase(binary), &1)) do
      words = Enum.map_join(words(), "|", &Regex.escape/1)
      key = "[^\\s&=?\"]*(?:#{words})[^\\s&=\"]*"

      binary
      |> then(&Regex.replace(~r/(#{key}=)[^&\s]*/i, &1, "\\1#{@filtered}"))
      |> then(&Regex.replace(~r/("#{key}"\s*:\s*)"(?:[^"\\]|\\.)*"/i, &1, ~s(\\1"#{@filtered}")))
    else
      binary
    end
  rescue
    _ -> @filtered
  end

  defp sensitive?(key) when is_atom(key), do: sensitive?(Atom.to_string(key))

  defp sensitive?(key) when is_binary(key) do
    key = String.downcase(key)
    Enum.any?(words(), &String.contains?(key, &1))
  end

  defp sensitive?(_key), do: false

  defp words, do: Application.fetch_env!(:dawarich, __MODULE__)[:words]
end
