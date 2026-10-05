defmodule Dawarich.Imports.ActivityBackfiller do
  @moduledoc false
  alias Dawarich.Imports.ActivityBackfill.File

  def call(repo, import_id, context \\ %{}) do
    case repo.query!("SELECT source FROM imports WHERE id=$1", [import_id], log: false).rows do
      [[source]] when source in [0, 1, 2, 3, 6] ->
        case File.attachment(repo, import_id) do
          nil -> false
          blob -> process(source, blob, context)
        end

      _ ->
        false
    end
  end

  defp process(source, _blob, _context) when source in [1, 2, 6], do: true

  defp process(_source, blob, context) do
    File.with_file(blob, context, fn _path -> :ok end)
    true
  end
end
