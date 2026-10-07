defmodule Dawarich.Imports.Progress do
  @moduledoc false
  alias Dawarich.Imports.NativeOwnership
  alias Dawarich.RailsCommands

  def publish!(repo, import, locale) do
    [[source]] =
      repo.query!(
        "SELECT source FROM imports WHERE id=$1 AND user_id=$2",
        [import.id, import.user_id],
        log: false
      ).rows

    parent = if source == 4, do: "imports.process_gpx", else: "imports.process_normal"

    if NativeOwnership.lock(repo, "command:" <> parent) == :sidekiq do
      RailsCommands.insert!(repo, "imports.progress", %{
        "user_id" => import.user_id,
        "import_id" => import.id,
        "locale" => locale
      })
    end

    :ok
  end
end
