defmodule Dawarich.Imports.Csv.Records do
  @moduledoc false
  defmodule Error do
    defexception message: "Malformed CSV", rails_class: "CSV::MalformedCSVError"
  end

  def parse("", _delimiter), do: nil
  def parse(line, <<delimiter>>), do: scan(line, delimiter, [], [], :bare)

  defp scan("", _, _, _, :quoted), do: fail("Unclosed quoted field")
  defp scan("", _, field, fields, mode), do: finish(field, fields, mode)

  defp scan(<<34, 34, rest::binary>>, delim, field, fields, :quoted),
    do: scan(rest, delim, [34 | field], fields, :quoted)

  defp scan(<<34, rest::binary>>, delim, field, fields, :quoted),
    do: scan(rest, delim, field, fields, :closed)

  defp scan(<<34, rest::binary>>, delim, [], fields, :bare),
    do: scan(rest, delim, [], fields, :quoted)

  defp scan(<<34, _::binary>>, _, _, _, :bare), do: fail("Illegal quoting")

  defp scan(<<byte, rest::binary>>, delim, field, fields, :quoted),
    do: scan(rest, delim, [byte | field], fields, :quoted)

  defp scan(<<delim, rest::binary>>, delim, field, fields, mode),
    do: scan(rest, delim, [], [value(field, mode) | fields], :bare)

  defp scan(<<byte, _::binary>>, _, [], [], :bare) when byte in [10, 13], do: []

  defp scan(<<byte, _::binary>>, _, field, fields, mode) when byte in [10, 13],
    do: finish(field, fields, mode)

  defp scan(_, _, _, _, :closed), do: fail("Any value after quoted field isn't allowed")

  defp scan(<<byte, rest::binary>>, delim, field, fields, :bare),
    do: scan(rest, delim, [byte | field], fields, :bare)

  defp finish(field, fields, mode), do: Enum.reverse([value(field, mode) | fields])
  defp value([], :bare), do: nil
  defp value(field, _), do: field |> Enum.reverse() |> :erlang.list_to_binary()
  defp fail(message), do: raise(Error, message: message <> " in line 1.")
end
