defmodule Dawarich.Imports.Kml.Handler do
  @moduledoc false
  alias Dawarich.Imports.JsonStream.Spool

  def with_state(dir, fun) do
    File.open!(Path.join(dir, "placemark"), [:write, :binary, :raw], fn placemarks ->
      File.open!(Path.join(dir, "track"), [:write, :binary, :raw], fn tracks ->
        state = %{
          dir: dir,
          indexes: %{placemark: placemarks, track: tracks},
          path: [],
          index: 0,
          captures: []
        }

        try do
          fun.(state)
        after
          for io <- Process.get({__MODULE__, dir}, []), do: File.close(io)
          Process.delete({__MODULE__, dir})
        end
      end)
    end)
  end

  def event({:startElement, uri, name, {prefix, _}, attrs}, _, s) do
    if length(s.path) >= 64, do: raise(ArgumentError, "KML XML depth exceeds limit")

    name =
      if prefix == [],
        do: List.to_string(name),
        else: List.to_string(prefix) <> ":" <> List.to_string(name)

    attrs =
      Map.new(attrs, fn {_, _, key, value} -> {List.to_string(key), List.to_string(value)} end)

    path = [{name, s.index, attrs} | s.path]

    kind =
      cond do
        name == "Placemark" ->
          :placemark

        List.to_string(uri) == "http://www.google.com/kml/ext/2.2" and
            String.ends_with?(name, ":Track") ->
          :track

        true ->
          nil
      end

    s =
      if kind do
        file = Path.join(s.dir, "object-#{s.index}")
        io = File.open!(file, [:write, :binary, :raw, :exclusive])
        File.chmod!(file, 0o600)
        Process.put({__MODULE__, s.dir}, [io | Process.get({__MODULE__, s.dir}, [])])
        %{s | captures: [{kind, s.index, io, file} | s.captures]}
      else
        s
      end

    s = %{s | path: path, index: s.index + 1}
    write(s, {:start, path})
    s
  end

  def event({:characters, chars}, _, s) do
    write(s, {:text, s.path, List.to_string(chars)})
    s
  end

  def event({:ignorableWhitespace, chars}, loc, s), do: event({:characters, chars}, loc, s)

  def event({:endElement, _, _, _}, _, s) do
    write(s, {:end, s.path})
    [{_, id, _} | tail] = s.path
    {closed, remaining} = Enum.split_with(s.captures, fn {_, root, _, _} -> root == id end)

    for {kind, _, io, file} <- closed do
      File.close(io)
      Process.put({__MODULE__, s.dir}, List.delete(Process.get({__MODULE__, s.dir}), io))
      Spool.write!(s.indexes[kind], file)
    end

    %{s | path: tail, captures: remaining}
  end

  def event(_, _, s), do: s
  defp write(s, event), do: Enum.each(s.captures, fn {_, _, io, _} -> Spool.write!(io, event) end)
end
