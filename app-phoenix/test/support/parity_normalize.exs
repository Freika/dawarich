# usage: MIX_ENV=test mix run --no-start test/support/parity_normalize.exs <dir>
# Writes <page>.dom.txt next to every <page>.html: the normalized <body>, one node per line.
defmodule ParityNormalize do
  def lines(nodes, depth \\ 0), do: Enum.flat_map(nodes, &line(&1, depth))

  defp line(text, depth) when is_binary(text), do: [indent(depth) <> inspect(text)]

  defp line({tag, attrs, children}, depth) do
    attrs = Enum.map_join(attrs, "", fn {name, value} -> " #{name}=#{inspect(value)}" end)
    [indent(depth) <> "<" <> tag <> attrs <> ">" | lines(children, depth + 1)]
  end

  defp indent(depth), do: String.duplicate("  ", depth)
end

[dir] = System.argv()

for path <- Path.wildcard(Path.join(dir, "**/*.html")) do
  dom =
    path
    |> File.read!()
    |> Dawarich.Test.ParityHTML.fragment("body")
    |> ParityNormalize.lines()

  File.write!(Path.rootname(path) <> ".dom.txt", Enum.join(dom, "\n") <> "\n")
end
