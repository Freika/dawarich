defmodule Dawarich.Imports.Progress do
  @moduledoc false
  alias Dawarich.Imports.NativeOwnership
  alias Dawarich.RailsCommands

  def publish!(repo, import, locale, lane \\ nil) do
    lane = lane || source_lane(repo, import)

    if NativeOwnership.lock(repo, lane) == :sidekiq do
      RailsCommands.insert!(repo, "imports.progress", %{
        "user_id" => import.user_id,
        "import_id" => import.id,
        "locale" => locale
      })
    end

    :ok
  end

  defp source_lane(repo, import) do
    [[source]] =
      repo.query!(
        "SELECT source FROM imports WHERE id=$1 AND user_id=$2",
        [import.id, import.user_id],
        log: false
      ).rows

    if source == 4, do: "command:imports.process_gpx", else: "command:imports.process_normal"
  end
end
