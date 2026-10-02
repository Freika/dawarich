defmodule Dawarich.EnhancedImport.GpxHandler do
  @moduledoc false

  alias Dawarich.EnhancedImport.GpxPlace
  alias Dawarich.ReleaseMigration

  def new(acc, fun),
    do: %{
      acc: acc,
      fun: fun,
      attrs: nil,
      fields: %{},
      field: nil,
      depth: 0,
      text: [],
      cdata: false
    }

  def event({:startElement, _uri, ~c"wpt", _qname, attributes}, _location, s) do
    attrs =
      Map.new(attributes, fn {_uri, _prefix, name, value} ->
        {List.to_string(name), List.to_string(value)}
      end)

    %{s | attrs: attrs, fields: %{}, field: nil, depth: 0}
  end

  def event({:startElement, _uri, _name, _qname, _attributes}, _location, %{attrs: nil} = s),
    do: s

  def event({:startElement, _uri, name, _qname, _attributes}, _location, s) do
    s = %{s | depth: s.depth + 1}
    name = List.to_string(name)
    if s.field == nil and capturable?(name, s.depth), do: %{s | field: name, text: []}, else: s
  end

  def event(:startCDATA, _location, s), do: %{s | cdata: true}
  def event(:endCDATA, _location, s), do: %{s | cdata: false}

  def event({:ignorableWhitespace, chars}, location, s),
    do: event({:characters, chars}, location, s)

  def event({:characters, chars}, _location, %{field: field, cdata: false} = s)
      when field != nil,
      do: %{s | text: [s.text, chars]}

  def event({:endElement, _uri, ~c"wpt", _qname}, _location, s),
    do: %{emit(s) | attrs: nil, fields: %{}, field: nil, depth: 0}

  def event({:endElement, _uri, _name, _qname}, _location, %{attrs: nil} = s), do: s

  def event({:endElement, _uri, name, _qname}, _location, s) do
    name = List.to_string(name)

    if s.field == name do
      value = ReleaseMigration.ruby_strip(List.to_string(s.text))
      %{s | fields: Map.put(s.fields, name, value), field: nil, text: [], depth: s.depth - 1}
    else
      %{s | depth: s.depth - 1}
    end
  end

  def event(_event, _location, s), do: s

  defp capturable?(name, depth), do: (name in ~w(name type) and depth == 1) or name == "color"

  defp emit(s) do
    case GpxPlace.build(s.attrs, s.fields) do
      nil -> s
      place -> %{s | acc: write(s.fun, place, s.acc)}
    end
  end

  defp write(fun, place, acc) do
    fun.(place, acc)
  rescue
    exception -> throw({:writer_error, {exception, __STACKTRACE__}})
  end
end
