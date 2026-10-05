defmodule Dawarich.Build do
  @moduledoc false

  def root, do: Dawarich.RailsRoot.root()

  def write!(path, iodata) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, iodata)
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
