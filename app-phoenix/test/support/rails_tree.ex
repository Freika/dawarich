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
end
