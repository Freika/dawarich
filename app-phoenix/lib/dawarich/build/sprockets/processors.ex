defmodule Dawarich.Build.Sprockets.Processors do
  @moduledoc false

  @url ~r/url\(\s*["']?(?!(?:\#|data|http))(?<rel>\.\/)?(?<path>[^"'\s)]+)\s*["']?\)/
  @sourcemap ~r{//# sourceMappingURL=(.*\.map)}
  @erb ~r/<%=\s*asset_path(?:\s*\(\s*|\s+)(["'])([^"']+)\1\s*\)?\s*%>/
  @uri ~r{\A(?:[-a-z]+://|cid:|data:|//)}i
  @tail ~r/[?#].+\z/

  def read_text(file, kind) do
    data = file |> File.read!() |> strip_bom(file)
    String.valid?(data) || raise(ArgumentError, "#{file} is not valid UTF-8")
    if kind == :css, do: strip_charset(data, file), else: data
  end

  def concat_js(parts), do: Enum.reduce(parts, "", &append_js(&2, &1))

  def url_paths(text),
    do: @url |> Regex.scan(text, capture: ["path"]) |> List.flatten() |> Enum.uniq()

  def rewrite_urls(text, urls),
    do:
      Regex.replace(@url, text, fn _match, _rel, path ->
        "url(" <> Map.fetch!(urls, path) <> ")"
      end)

  def sourcemap_refs(text),
    do: @sourcemap |> Regex.scan(text, capture: :all_but_first) |> List.flatten() |> Enum.uniq()

  def rewrite_sourcemaps(text, refs),
    do: Regex.replace(@sourcemap, text, fn _match, ref -> Map.fetch!(refs, ref) end)

  def sibling(logical, ref) do
    case Path.dirname(logical) do
      "." -> ref
      dir -> dir <> "/" <> ref
    end
  end

  def erb_paths(text, file) do
    if Regex.match?(~r/^<%.*%>$/m, text),
      do: raise(ArgumentError, "#{file}: an ERB tag filling a whole line is not supported")

    if String.contains?(Regex.replace(@erb, text, ""), "<%"),
      do: raise(ArgumentError, "#{file}: ERB assets may only call asset_path")

    @erb |> Regex.scan(text, capture: :all_but_first) |> Enum.map(&List.last/1) |> Enum.uniq()
  end

  def render_erb(text, urls),
    do: Regex.replace(@erb, text, fn _match, _quote, path -> Map.fetch!(urls, path) end)

  def uri?(path), do: Regex.match?(@uri, path)

  def split_tail(path) do
    case Regex.run(@tail, path, return: :index) do
      [{start, _}] ->
        {binary_part(path, 0, start), binary_part(path, start, byte_size(path) - start)}

      nil ->
        {path, ""}
    end
  end

  defp append_js(buf, ""), do: buf

  defp append_js(buf, part) do
    last = :binary.last(part)

    cond do
      semicolon_end?(part) -> buf <> part
      last in [?\n, ?\s, ?\t] -> buf <> binary_part(part, 0, byte_size(part) - 1) <> <<?;, last>>
      true -> buf <> part <> ";"
    end
  end

  defp semicolon_end?(part) do
    stripped = Regex.replace(~r/[\n \t]+\z/, part, "")
    stripped == "" or String.ends_with?(stripped, ";")
  end

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>, _file), do: rest

  defp strip_bom(<<a, b, _::binary>>, file) when {a, b} in [{0xFE, 0xFF}, {0xFF, 0xFE}],
    do: raise(ArgumentError, "#{file}: UTF-16 sources are not supported")

  defp strip_bom(data, _file), do: data

  defp strip_charset(<<"@charset \"", rest::binary>> = data, file) do
    case :binary.match(rest, "\"") do
      {pos, 1} ->
        name = binary_part(rest, 0, pos)

        unless String.downcase(name) == "utf-8",
          do: raise(ArgumentError, "#{file}: @charset #{name} is not supported")

        length = byte_size(~s(@charset "#{name}";))
        binary_part(data, length, byte_size(data) - length)

      :nomatch ->
        data
    end
  end

  defp strip_charset(data, _file), do: data
end
