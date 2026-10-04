defmodule Dawarich.Imports.Tcx.Handler do
  @moduledoc false
  alias Dawarich.Imports.ParserLimit
  alias Dawarich.Imports.JsonStream.Spool

  def new(io), do: %{io: io, path: [], sport: nil, frames: [], bytes: 0, nodes: 0}

  def event({:startElement, _, name, _, attrs}, _, s) do
    if length(s.path) >= 64, do: raise(ParserLimit, "TCX XML depth exceeds limit")
    name = List.to_string(name)
    path = [name | s.path]
    s = %{s | path: path}

    s =
      if path == ["Activity", "Activities", "TrainingCenterDatabase"],
        do: %{s | sport: sport(attrs)},
        else: s

    if s.frames != [] or
         path == [
           "Trackpoint",
           "Track",
           "Lap",
           "Activity",
           "Activities",
           "TrainingCenterDatabase"
         ] do
      nodes = s.nodes + 1

      bytes =
        s.bytes + byte_size(name) + 32 +
          Enum.reduce(attrs, 0, fn {_, _, key, value}, total ->
            total + length(key) * 4 + length(value) * 4
          end)

      if nodes > 1024, do: raise(ParserLimit, "TCX trackpoint node count exceeds limit")
      if bytes > 1_048_576, do: raise(ParserLimit, "TCX trackpoint exceeds limit")
      %{s | frames: [{name, %{}, []} | s.frames], nodes: nodes, bytes: bytes}
    else
      s
    end
  end

  def event({:characters, chars}, _, %{frames: [{name, children, text} | tail]} = s) do
    value = List.to_string(chars)
    bytes = s.bytes + byte_size(value)
    if bytes > 1_048_576, do: raise(ParserLimit, "TCX trackpoint exceeds limit")
    %{s | bytes: bytes, frames: [{name, children, [value | text]} | tail]}
  end

  def event({:ignorableWhitespace, chars}, loc, s), do: event({:characters, chars}, loc, s)

  def event({:endElement, _, _, _}, _, %{frames: [{name, children, text} | tail]} = s) do
    value = if children == %{}, do: scalar(text), else: children

    case tail do
      [] ->
        Spool.write!(s.io, {s.sport, value})
        %{s | path: tl(s.path), frames: [], bytes: 0, nodes: 0}

      [{parent, siblings, parent_text} | rest] ->
        siblings = Map.update(siblings, name, value, fn old -> List.wrap(old) ++ [value] end)
        %{s | path: tl(s.path), frames: [{parent, siblings, parent_text} | rest]}
    end
  end

  def event({:endElement, _, _, _}, _, s), do: %{s | path: tl(s.path)}
  def event(_, _, s), do: s

  defp scalar(text) do
    value = text |> Enum.reverse() |> IO.iodata_to_binary()
    if String.trim(value) == "", do: nil, else: value
  end

  defp sport(attrs) do
    Enum.find_value(attrs, fn {_, _, key, value} ->
      if key == ~c"Sport", do: List.to_string(value)
    end)
  end
end
