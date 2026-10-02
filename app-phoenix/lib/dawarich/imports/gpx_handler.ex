defmodule Dawarich.Imports.GpxHandler do
  @moduledoc false
  @max_depth 64
  @max_point 1_048_576

  def new(import, acc, fun),
    do: %{
      import: import,
      acc: acc,
      fun: fun,
      counts: %{},
      depth: 0,
      stack: nil,
      text: "",
      trk: -1,
      seg: -1,
      identity: nil,
      source: nil,
      capture: nil,
      capture_depth: 0,
      cdata: false,
      point_bytes: 0
    }

  def event({:startElement, uri, name, {prefix, _}, attrs}, _, s) do
    if s.depth >= @max_depth, do: raise(ArgumentError, "GPX parse error: XML depth exceeds limit")
    s = %{s | depth: s.depth + 1}
    s = if prefix != [] and uri == [], do: count(s, "parse_errors_seen"), else: s

    s =
      Enum.reduce(attrs, s, fn {attr_uri, attr_prefix, _, _}, state ->
        if attr_prefix != [] and attr_uri == [],
          do: count(state, "parse_errors_seen"),
          else: state
      end)

    start(List.to_string(name), attrs, s)
  end

  def event({:endElement, _, name, _}, _, s),
    do: finish(List.to_string(name), %{s | depth: s.depth - 1})

  def event(:startCDATA, _, s), do: %{s | cdata: true}
  def event(:endCDATA, _, s), do: %{s | cdata: false}
  def event({:ignorableWhitespace, chars}, loc, s), do: event({:characters, chars}, loc, s)
  def event({:characters, _}, _, %{cdata: true} = s), do: s
  def event({:characters, _}, _, %{capture_depth: n} = s) when n > 0, do: s

  def event({:characters, chars}, _, s) do
    if s.stack || s.capture do
      text = s.text <> List.to_string(chars)

      if byte_size(text) > @max_point,
        do: raise(ArgumentError, "GPX parse error: field token exceeds limit")

      s = if s.stack, do: budget(s, byte_size(List.to_string(chars))), else: s
      %{s | text: text}
    else
      s
    end
  end

  def event(_, _, s), do: s

  defp start("trk", _, s),
    do: %{s | trk: s.trk + 1, seg: -1, identity: nil, source: nil, capture: nil, capture_depth: 0}

  defp start("trkseg", _, s), do: %{s | seg: s.seg + 1}
  defp start("wpt", _, s), do: count(s, "waypoints_seen")
  defp start("rtept", _, s), do: count(s, "route_points_seen")
  defp start(_, _, %{capture: c} = s) when c != nil, do: %{s | capture_depth: s.capture_depth + 1}

  defp start(name, _, %{stack: nil, trk: trk, seg: seg} = s)
       when trk >= 0 and seg < 0 and name in ["src", "name"],
       do: %{s | capture: name, capture_depth: 0, text: ""}

  defp start("trkpt", attrs, %{stack: nil} = s) do
    fields = attributes(attrs)
    s = budget(%{s | point_bytes: 0}, :erlang.external_size(fields))
    %{count(s, "trackpoints_seen") | stack: [fields], text: ""}
  end

  defp start(name, attrs, %{stack: [parent | tail]} = s) do
    fields = attributes(attrs)
    s = budget(s, byte_size(name) + :erlang.external_size(fields))
    %{s | stack: [fields, Map.put(parent, name, fields) | tail], text: ""}
  end

  defp start(_, _, s), do: s

  defp finish(_, %{capture: c, capture_depth: n} = s) when c != nil and n > 0,
    do: %{s | capture_depth: n - 1}

  defp finish(name, %{capture: name} = s) when name != nil do
    value = strip(s.text)

    s =
      if value != "" and not (name == "name" and s.source == "src"),
        do: %{s | identity: value, source: name},
        else: s

    %{s | capture: nil, text: ""}
  end

  defp finish(name, s) when name in ["trk", "trkseg"], do: s
  defp finish(_, %{stack: nil} = s), do: s

  defp finish(_, %{stack: [point]} = s) do
    acc =
      try do
        s.fun.(point, tracker(s), s.acc)
      catch
        kind, reason -> throw({:gpx_callback_error, {kind, reason, __STACKTRACE__}})
      end

    %{s | acc: acc, stack: nil, text: ""}
  end

  defp finish(name, %{stack: [closed, parent | tail]} = s) do
    value = if map_size(closed) == 0, do: strip(s.text), else: closed
    %{s | stack: [Map.put(parent, name, value) | tail], text: ""}
  end

  defp attributes(attrs),
    do:
      Map.new(attrs, fn {_, _, name, value} -> {List.to_string(name), List.to_string(value)} end)

  defp count(s, key), do: %{s | counts: Map.update(s.counts, key, 1, &(&1 + 1))}

  defp budget(s, n) do
    if s.point_bytes + n > @max_point,
      do: raise(ArgumentError, "GPX parse error: point token exceeds limit")

    %{s | point_bytes: s.point_bytes + n}
  end

  defp strip(text),
    do:
      String.trim(text, "\u0000") |> String.replace(~r/\A[\x09-\x0D\x20]+|[\x09-\x0D\x20]+\z/, "")

  defp tracker(%{trk: trk, import: import}) when trk < 0, do: "import-#{import.id}-orphan"

  defp tracker(s) do
    key =
      if s.identity do
        identity =
          if s.source == "src", do: s.identity, else: "#{s.identity}|import:#{s.import.name}"

        digest = :crypto.hash(:sha, identity) |> Base.encode16(case: :lower) |> binary_part(0, 16)
        "gpx-#{digest}-trk-#{s.trk}"
      else
        "import-#{s.import.id}-trk-#{s.trk}"
      end

    "#{key}-seg-#{max(s.seg, 0)}"
  end
end
