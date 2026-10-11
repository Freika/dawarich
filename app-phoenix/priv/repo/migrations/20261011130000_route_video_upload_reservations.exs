defmodule Dawarich.Repo.Migrations.RouteVideoUploadReservations do
  use Ecto.Migration

  def up, do: replace("'imports','account','rich_text','route_video'")
  def down, do: replace("'imports','account','rich_text'")

  defp replace(kinds) do
    drop constraint(:native_uploads, :native_upload_states, prefix: "phoenix")

    create constraint(:native_uploads, :native_upload_states,
             prefix: "phoenix",
             check:
               "state IN ('pending','claimed','cancelled','expired','purged') AND kind IN (#{kinds}) AND (original_size > 0 OR (kind='rich_text' AND original_size=0))"
           )
  end
end
