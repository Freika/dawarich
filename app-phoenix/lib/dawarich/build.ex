defmodule Dawarich.Build do
  @moduledoc false

  def root, do: Dawarich.RailsRoot.root()

  def write!(path, iodata) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, iodata)
  end

  def runtime_data!(root, out) do
    priv = Application.app_dir(:dawarich, "priv")

    for {source, retained, target} <- [
          {"app-phoenix/priv/time_zones.json", "time_zones.json", "tmp/phoenix/time_zones.json"},
          {"config/shared_link_wordlist.txt", "shared_link_wordlist.txt",
           "priv/shared_link_wordlist.txt"},
          {"lib/assets/countries.geojson.gz", "countries.geojson.gz",
           "priv/countries.geojson.gz"},
          {"lib/assets/admin1_world.geojson", "admin1_world.geojson", "priv/admin1_world.geojson"}
        ] do
      input = Path.join(root, source)
      input = if File.regular?(input), do: input, else: Path.join(priv, retained)
      write!(Path.join(out, target), File.read!(input))
    end
  end

  def refresh!(target, root, fun) do
    if stale?(target, sources(root)), do: write!(target, fun.())
    :ok
  end

  defp stale?(target, sources) do
    case File.stat(target, time: :posix) do
      {:ok, %{mtime: built}} -> Enum.any?(sources, &(File.stat!(&1, time: :posix).mtime > built))
      {:error, _} -> true
    end
  end

  defp sources(root) do
    Enum.flat_map(
      [
        Path.join(root, "config/locales/**/*.yml"),
        Path.join(root, "config/achievements.yml"),
        Path.join(root, "config/achievements/*.yml"),
        Path.join(__DIR__, "build/**/*.ex")
      ],
      &Path.wildcard/1
    )
  end
end
