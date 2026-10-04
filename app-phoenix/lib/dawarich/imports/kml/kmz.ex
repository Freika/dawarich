defmodule Dawarich.Imports.Kml.Kmz do
  @moduledoc false
  alias Dawarich.Imports.{ArchivePaths, Tempfiles}
  alias Dawarich.Imports.GpxArchive.{Directory, Error}

  def with_kml(path, context, fun) do
    entry =
      File.open!(path, [:read, :binary, :raw], fn file ->
        file
        |> Directory.read!([])
        |> Map.fetch!(:entries)
        |> Enum.find(&String.ends_with?(String.downcase(&1.name), ".kml"))
      end)

    unless entry, do: raise(Error, message: "No KML file found in KMZ archive")

    Tempfiles.with_files(fn adopt ->
      opts = [on_verified: adopt]
      opts = if context[:temp_dir], do: Keyword.put(opts, :temp_dir, context.temp_dir), else: opts
      extracted = ArchivePaths.extract(path, entry, opts)
      fun.(extracted)
    end)
  end
end
