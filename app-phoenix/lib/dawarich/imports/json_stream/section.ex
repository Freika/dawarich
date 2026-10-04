defmodule Dawarich.Imports.JsonStream.Section do
  @moduledoc false
  alias Dawarich.Imports.JsonStream

  def last(path, key) do
    shape =
      JsonStream.reduce(
        path,
        %{},
        fn event, state -> record(event, state, key) end,
        fn parts -> if parts in [[], [key]], do: :scalar, else: false end,
        mode: :compat
      )

    {Map.get(shape, :root), Map.get(shape, :section)}
  end

  def reduce(path, %{kind: :array, offset: offset, length: length}, acc, fun) do
    JsonStream.reduce(
      path,
      acc,
      fn
        {:value, [index], value, _, _}, acc when is_integer(index) -> fun.(value, acc)
        _, acc -> acc
      end,
      fn
        [index] when is_integer(index) -> true
        _ -> false
      end,
      mode: :compat,
      offset: offset,
      length: length
    )
  end

  def reduce(_path, _section, acc, _fun), do: acc

  defp record({:start, kind, parts, offset}, state, key) when parts == [] or parts == [key] do
    Map.put(state, field(parts), %{kind: kind, offset: offset})
  end

  defp record({:value, parts, value, offset, ending}, state, key)
       when parts == [] or parts == [key] do
    field = field(parts)
    previous = Map.get(state, field)
    kind = if previous && previous.offset == offset, do: previous.kind, else: :scalar
    Map.put(state, field, %{kind: kind, value: value, offset: offset, length: ending - offset})
  end

  defp record(_, state, _key), do: state
  defp field([]), do: :root
  defp field(_), do: :section
end
