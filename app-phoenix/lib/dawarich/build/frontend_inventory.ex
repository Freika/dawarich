defmodule Dawarich.Build.FrontendInventory do
  @moduledoc false

  @sources ["lib/**/*.{ex,heex}", "priv/static/js/**/*.js", "assets/js/**/*.js"]
  @tests ["test/**/*.exs"]

  @patterns [
    stimulus: ~r/data-controller(?:=|"\s*=>\s*)(?:"([^"]+)"|\{([^}]*)\})/,
    hook: ~r/phx-hook=(?:"([A-Za-z0-9_.]+)"|\{([^}]*)\})/,
    turbo: ~r/\b(data-turbo[a-z-]*|turbo-frame|turbo-stream)\b/,
    action_cable: ~r/\b(createConsumer|ActionCable)\b/,
    action_text: ~r/(@rails\/actiontext|\btrix\b)/,
    direct_upload: ~r/\b(direct_uploads)\b/,
    live_session: ~r/live_session\s+:([a-z_]+)/
  ]

  @markup ~r/LazyHTML\.query\((?:[^,()"]+,\s*)?"([^"]*(?:\.[a-z][\w-]*|data-turbo|data-controller)[^"]*)"/

  def scan(root) do
    sources = Enum.flat_map(files(root, @sources), &findings(root, &1, @patterns))
    tests = Enum.flat_map(files(root, @tests), &findings(root, &1, markup_assertion: @markup))
    Enum.sort_by(sources ++ tests, &{&1.file, &1.kind, &1.value})
  end

  def graph(%{"inputs" => inputs}, entries) do
    roots = for entry <- entries, do: edge("<entry>", entry, "entry-point")

    Enum.sort_by(
      roots ++ walk(inputs, entries, MapSet.new()),
      &{&1.file, &1.value, &1.import_kind}
    )
  end

  def hotwire?(%{kind: kind}) when kind in [:stimulus, :turbo, :action_cable],
    do: true

  def hotwire?(%{kind: :hook, value: "RailsStimulus"}), do: true

  def hotwire?(%{kind: :module, value: path}),
    do:
      Regex.match?(
        ~r/(?:^|\/)@hotwired\/|(?:^|\/)@rails\/actiontext(?:\/|$)|(?:^|\/)(?:rails_bridge|map_shell|family_page)\.js$/,
        path
      )

  def hotwire?(_finding), do: false

  defp walk(_inputs, [], _seen), do: []

  defp walk(inputs, [path | rest], seen) do
    if MapSet.member?(seen, path) do
      walk(inputs, rest, seen)
    else
      imports = get_in(inputs, [path, "imports"]) || []
      edges = for import <- imports, do: edge(path, import["path"], import["kind"])
      children = for import <- imports, import["external"] != true, do: import["path"]
      edges ++ walk(inputs, children ++ rest, MapSet.put(seen, path))
    end
  end

  defp edge(parent, path, kind),
    do: %{file: parent, kind: :module, value: path, import_kind: kind}

  defp files(root, globs),
    do: globs |> Enum.flat_map(&Path.wildcard(Path.join(root, &1))) |> Enum.uniq()

  defp findings(root, path, patterns) do
    text = File.read!(path)
    file = Path.relative_to(path, root)

    for {kind, regex} <- patterns,
        [_ | groups] <- Regex.scan(regex, text),
        captured <- Enum.reject(groups, &(&1 == "")),
        literal <- literals(captured),
        value <- values(kind, literal),
        uniq: true,
        do: %{file: file, kind: kind, value: value}
  end

  defp literals(captured) do
    case Regex.scan(~r/"([^"]+)"/, captured, capture: :all_but_first) do
      [] -> [captured]
      quoted -> List.flatten(quoted)
    end
  end

  defp values(:stimulus, captured), do: String.split(captured)
  defp values(_kind, captured), do: [captured]
end
