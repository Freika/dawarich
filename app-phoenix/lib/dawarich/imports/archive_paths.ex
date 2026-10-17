defmodule Dawarich.Imports.ArchivePaths do
  @moduledoc false
  alias Dawarich.Imports.GpxArchive

  def extract(path, entry, opts \\ []), do: GpxArchive.extract_entry!(path, entry, opts)
end
