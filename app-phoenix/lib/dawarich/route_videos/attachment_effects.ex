defmodule Dawarich.RouteVideos.AttachmentEffects do
  @moduledoc false

  def enqueue!(repo, payload) do
    if valid?(repo, payload),
      do: Dawarich.Exports.PurgeWorker.enqueue!(repo, [payload["blob_id"]])

    :ok
  end

  def cleanup_failed_save!(repo, user_id, blob_id) do
    if attached?(repo, blob_id) do
      :ok
    else
      Dawarich.RouteVideos.AttachmentJob.enqueue!(repo, %{
        "user_id" => user_id,
        "blob_id" => blob_id,
        "action" => "purge_unattached"
      })
    end
  end

  defp attached?(repo, blob_id),
    do:
      repo.query!(
        "SELECT EXISTS(SELECT 1 FROM active_storage_attachments WHERE blob_id=$1)",
        [blob_id],
        log: false
      ).rows == [[true]]

  defp valid?(repo, payload) do
    positive?(payload, ["user_id", "blob_id"]) and
      case payload["action"] do
        "purge_unattached" -> true
        "purge_detached" -> detached?(repo, payload)
        _ -> false
      end
  end

  defp detached?(repo, %{"attachment" => identity} = payload) when is_map(identity) do
    positive?(identity, ["id", "record_id", "blob_id"]) and
      identity["name"] == "file" and identity["record_type"] == "RouteVideo" and
      identity["blob_id"] == payload["blob_id"] and
      repo.query!("SELECT id FROM active_storage_attachments WHERE id=$1", [identity["id"]],
        log: false
      ).rows == [] and
      repo.query!("SELECT user_id FROM route_videos WHERE id=$1", [identity["record_id"]],
        log: false
      ).rows in [[], [[payload["user_id"]]]]
  end

  defp detached?(_repo, _payload), do: false

  defp positive?(payload, fields),
    do: Enum.all?(fields, &(is_integer(payload[&1]) and payload[&1] > 0))
end
