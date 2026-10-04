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
      {:legacy, reason} -> raise Error, message: "Unsupported normal import archive: #{reason}"
    end
  rescue
    error in Error ->
      if error.message == "ZIP central directory is missing",
        do: :not_a_zip,
        else: reraise(error, __STACKTRACE__)
  end
end
