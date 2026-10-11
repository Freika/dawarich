defmodule Dawarich.Build.NativeDependencyGraph do
  @moduledoc false
  alias Dawarich.Build.FrontendInventory

  @runtime ~r/(?:\b(?:window|globalThis)\.(?:Turbo|Stimulus|StimulusIslands)\b|\b(?:bootRailsBridges|bootTurboFrames|RailsStimulus)\b|@hotwired\/|@rails\/actiontext)/
  @references ~r/(?:\bfrom\s*|\bimport\s*\(?\s*|new\s+URL\s*\(\s*)["']([^"']+)["']/

  def audit(meta, entries, source, public) do
    edges = FrontendInventory.graph(meta, entries)
    forbidden = Enum.filter(edges, &FrontendInventory.hotwire?/1)

    paths =
      edges
      |> Enum.map(& &1.value)
      |> Enum.filter(&String.starts_with?(&1, "/"))
      |> Enum.map(&Path.join(public, String.trim_leading(&1, "/")))

    inputs =
      edges
      |> Enum.map(& &1.value)
      |> Enum.filter(&Map.has_key?(meta["inputs"], &1))
      |> Enum.map(&Path.expand(&1, source))

    (forbidden ++ scan(inputs ++ paths, MapSet.new()))
    |> Enum.uniq()
  end

  def audit_files(paths), do: scan(paths, MapSet.new()) |> Enum.uniq()

  defp scan([], _seen), do: []

  defp scan([path | rest], seen) do
    if MapSet.member?(seen, path) do
      scan(rest, seen)
    else
      text = File.read!(path)

      found =
        for [value] <- Regex.scan(@runtime, text, capture: :first),
            do: %{file: path, kind: :runtime, value: value}

      children =
        for [ref] <- Regex.scan(@references, text, capture: :all_but_first),
            String.starts_with?(ref, "./") or String.starts_with?(ref, "../"),
            Path.extname(ref) in [".js", ".mjs"],
            do: Path.expand(ref, Path.dirname(path))

      found ++ scan(children ++ rest, MapSet.put(seen, path))
    end
  end
end
