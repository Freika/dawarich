defmodule Dawarich.Build.Sprockets.Directives do
  @moduledoc false

  @directive ~r/^\W*=\s*(\w+.*?)(\*\/)?$/
  @known ~w(require require_self require_directory require_tree depend_on depend_on_asset
            depend_on_directory stub link link_directory link_tree)

  def split(source) do
    size = header_size(source, 0, 0)
    {processed, directives} = extract(binary_part(source, 0, size))
    data = processed <> binary_part(source, size, byte_size(source) - size)
    data = if data != "" and not String.ends_with?(data, "\n"), do: data <> "\n", else: data
    {data, directives}
  end

  defp header_size(source, pos, last) do
    start = skip_space(source, pos)

    case source do
      <<_::binary-size(start), "//", _::binary>> ->
        stop = line_end(source, start)
        header_size(source, stop, stop)

      <<_::binary-size(start), "/*", _::binary>> ->
        case :binary.match(source, "*/", scope: {start + 2, byte_size(source) - start - 2}) do
          {close, 2} -> header_size(source, close + 2, close + 2)
          :nomatch -> last
        end

      _ ->
        last
    end
  end

  defp skip_space(source, pos) do
    case source do
      <<_::binary-size(pos), c, _::binary>> when c in [?\s, ?\t, ?\n, ?\r, ?\f, ?\v] ->
        skip_space(source, pos + 1)

      _ ->
        pos
    end
  end

  defp line_end(source, pos) do
    case :binary.match(source, "\n", scope: {pos, byte_size(source) - pos}) do
      {newline, 1} -> newline + 1
      :nomatch -> byte_size(source)
    end
  end

  defp extract(header) do
    {lines, directives} =
      header
      |> String.split(~r/(?<=\n)/, trim: true)
      |> Enum.map_reduce([], fn line, acc ->
        case parse(line) do
          {name, args} when name in @known -> {"\n", [{name, args} | acc]}
          _ -> {line, acc}
        end
      end)

    processed = lines |> IO.iodata_to_binary() |> chomp()

    processed =
      if processed != "" and String.ends_with?(header, "\n"),
        do: processed <> "\n",
        else: processed

    {processed, Enum.reverse(directives)}
  end

  defp parse(line) do
    case Regex.run(@directive, String.trim_trailing(line, "\n")) do
      [_, text | _] ->
        if String.contains?(text, ["\"", "'", "\\"]),
          do:
            raise(
              ArgumentError,
              "quoted Sprockets directive arguments are not supported: #{text}"
            )

        [name | args] = String.split(text)
        {name, args}

      nil ->
        nil
    end
  end

  defp chomp(text) do
    cond do
      String.ends_with?(text, "\r\n") -> binary_part(text, 0, byte_size(text) - 2)
      String.ends_with?(text, ["\n", "\r"]) -> binary_part(text, 0, byte_size(text) - 1)
      true -> text
    end
  end
end
