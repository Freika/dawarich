defmodule Dawarich.Imports.Kml.Handler do
  @moduledoc false
  alias Dawarich.Imports.JsonStream.Spool
  @capture_limit 65_536

  def with_state(dir, fun) do
    File.open!(
      Path.join(dir, "placemark"),
      [:write, :binary, :raw, :delayed_write],
      fn placemarks ->
        File.open!(Path.join(dir, "track"), [:write, :binary, :raw, :delayed_write], fn tracks ->
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
      end
    )
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
        capture = %{
          kind: kind,
          root: s.index,
          file: Path.join(s.dir, "object-#{s.index}"),
          io: nil,
          events: [],
          bytes: 0
        }

        %{s | captures: [capture | s.captures]}
      else
        s
      end

    s = %{s | path: path, index: s.index + 1}
    write(s, {:start, path})
  end

  def event({:characters, chars}, _, s) do
    write(s, {:text, s.path, List.to_string(chars)})
  end

  def event({:ignorableWhitespace, chars}, loc, s), do: event({:characters, chars}, loc, s)

  def event({:endElement, _, _, _}, _, s) do
    s = write(s, {:end, s.path})
    [{_, id, _} | tail] = s.path
    {closed, remaining} = Enum.split_with(s.captures, &(&1.root == id))

    for capture <- closed do
      value =
        if capture.io do
          :ok = File.close(capture.io)

          Process.put(
            {__MODULE__, s.dir},
            List.delete(Process.get({__MODULE__, s.dir}), capture.io)
          )

          capture.file
        else
          Enum.reverse(capture.events)
        end

      Spool.write!(s.indexes[capture.kind], value)
    end

    %{s | path: tail, captures: remaining}
  end

  def event(_, _, s), do: s

  defp write(s, event) do
    %{s | captures: Enum.map(s.captures, &write_capture(&1, event, s.dir))}
  end

  defp write_capture(%{io: io} = capture, event, _dir) when io != nil do
    Spool.write!(io, event)
    capture
  end

  defp write_capture(capture, event, dir) do
    bytes = capture.bytes + :erlang.external_size(event) + 8

    if bytes <= @capture_limit do
      %{capture | events: [event | capture.events], bytes: bytes}
    else
      io = File.open!(capture.file, [:write, :binary, :raw, :exclusive, :delayed_write])
      File.chmod!(capture.file, 0o600)
      Process.put({__MODULE__, dir}, [io | Process.get({__MODULE__, dir}, [])])
      Enum.each(Enum.reverse(capture.events), &Spool.write!(io, &1))
      Spool.write!(io, event)
      %{capture | io: io, events: [], bytes: 0}
    end
  end
end
