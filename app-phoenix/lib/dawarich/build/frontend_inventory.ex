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

  def hotwire?(%{kind: kind}) when kind in [:stimulus, :turbo, :action_cable, :direct_upload],
    do: true

  def hotwire?(%{kind: :hook, value: "RailsStimulus"}), do: true
  def hotwire?(_finding), do: false

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
