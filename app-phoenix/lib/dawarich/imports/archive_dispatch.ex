defmodule Dawarich.Imports.ArchiveDispatch do
  @moduledoc false
  alias Dawarich.Imports.GpxArchive
  alias Dawarich.Imports.GpxArchive.Error

  def inspect(path, opts \\ []) do
    case GpxArchive.inspect!(path, opts) do
      {:gpx, ^path} -> :not_a_zip
      {:entry, entry} -> {:single_entry, entry}
      {:legacy, :user_data_archive} -> :user_data_archive
      {:legacy, :multi_entry} -> :multi_entry
      {:legacy, reason} -> {:legacy, reason}
    end
  rescue
    error in Error ->
      cond do
        error.message == "ZIP central directory is missing" ->
          :not_a_zip

        error.message in [
          "Unsafe ZIP entry path",
          "Duplicate ZIP entry names",
          "ZIP entry is not a regular file or directory",
          "ZIP central directory exceeds metadata budget",
          "ZIP entry count exceeds budget",
          "Split ZIP archives are not supported",
          "Duplicate ZIP extra metadata"
        ] ->
          {:legacy, {:archive_policy, error.message}}

        true ->
          reraise(error, __STACKTRACE__)
      end
  end
end
