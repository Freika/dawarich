defmodule Dawarich.Imports.ActivityBackfiller do
  @moduledoc false
  alias Dawarich.Imports.ActivityBackfill.File

  def call(repo, import_id, context \\ %{}) do
    case repo.query!("SELECT source FROM imports WHERE id=$1", [import_id], log: false).rows do
      [[source]] when source in [0, 1, 2, 3, 6] ->
        case File.attachment(repo, import_id) do
          nil -> false
          blob -> process(repo, import_id, source, blob, context)
        end

      _ ->
        false
    end
  end

  defp process(_repo, _import_id, source, _blob, _context) when source in [1, 2, 6], do: true

  defp process(repo, import_id, source, blob, context) do
    context =
      context
      |> Map.put(:repo, repo)
      |> Map.put_new(:zone, "Etc/UTC")
      |> Map.put_new_lazy(:now, &DateTime.utc_now/0)

    File.with_file(blob, context, fn path ->
      if source == 0,
        do: Dawarich.Imports.ActivityBackfill.Semantic.run(repo, import_id, path, context)
    end)

    true
  end
end
