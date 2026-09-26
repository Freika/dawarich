defmodule Dawarich.RailsTree do
  @moduledoc false

  @root Path.expand("../../..", __DIR__)

  def states do
    @root
    |> Path.join("db/release_migrations.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("states")
  end

  def read(relative), do: @root |> Path.join(relative) |> File.read!()

  def split_at(release) do
    {before, [at | later]} = Enum.split_while(states(), &(&1["first_release"] != release))
    {before ++ [at], later}
  end

  def versions(directory) do
    @root
    |> Path.join("db/#{directory}/*.rb")
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case Regex.run(~r/\A(\d+)_/, Path.basename(path)) do
        [_, version] -> [version]
        nil -> []
      end
    end)
    |> Enum.sort()
  end

  def disables_ddl_transaction?(version) do
    [path] = Path.wildcard(Path.join(@root, "db/migrate/#{version}_*.rb"))

    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "#"))
    |> Enum.any?(&String.contains?(&1, "disable_ddl_transaction!"))
  end

  def defines_class?(relative_path, class_name) do
    path = Path.join(@root, relative_path)
    File.exists?(path) and class_defined?(File.read!(path), String.split(class_name, "::"))
  end

  defp class_defined?(source, parts) do
    {namespaces, [name]} = Enum.split(parts, -1)

    Regex.match?(~r/^\s*class\s+#{Regex.escape(Enum.join(parts, "::"))}\b/m, source) or
      (Regex.match?(~r/^\s*class\s+#{Regex.escape(name)}\b/m, source) and
         Enum.all?(namespaces, &Regex.match?(~r/^\s*module\s+#{Regex.escape(&1)}\b/m, source)))
  end
end
