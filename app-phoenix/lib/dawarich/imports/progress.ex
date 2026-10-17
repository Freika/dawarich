defmodule Dawarich.Imports.Progress do
  @moduledoc false
  alias Dawarich.Imports.NativeOwnership
  alias Dawarich.RailsCommands

  def publish!(repo, import, locale, lane \\ nil) do
    case source(repo, import) do
      [[source]] ->
        lane = lane || source_lane(source)

        if NativeOwnership.lock(repo, lane) == :sidekiq do
          RailsCommands.insert!(repo, "imports.progress", %{
            "user_id" => import.user_id,
            "import_id" => import.id,
            "locale" => locale
          })
        end

      [] ->
        :ok
    end

    :ok
  end

  def present?(repo, import), do: source(repo, import) != []

  defp source(repo, import) do
    repo.query!(
      "SELECT source FROM imports WHERE id=$1 AND user_id=$2",
      [import.id, import.user_id],
      log: false
    ).rows
  end

  defp source_lane(4), do: "command:imports.process_gpx"
  defp source_lane(_), do: "command:imports.process_normal"
end
