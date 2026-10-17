defmodule Dawarich.Uploads.DeletionDebt do
  @moduledoc false

  def transfer!(repo, object) do
    refs =
      repo.query!(
        "UPDATE phoenix.native_uploads u SET state='cancelled',object_key=$2,service_name=$3,cleanup_at=greatest(target_until+interval '1 second',timezone('UTC',now())) WHERE blob_id=$1 AND state='claimed' AND ((object_key=$2 AND service_name=$3) OR (object_key IS NULL AND EXISTS(SELECT 1 FROM phoenix.upload_receipts r WHERE r.blob_id=u.blob_id AND r.user_id=u.user_id))) RETURNING reference",
        [object["blob_id"], object["key"], object["service_name"]],
        log: false
      ).rows

    for [ref] <- refs,
        do:
          repo.insert!(Dawarich.Uploads.CleanupWorker.new(%{"reference" => ref}), prefix: "oban")

    :ok
  end

  def retained?(repo, object) do
    repo.query!(
      "SELECT 1 FROM phoenix.native_uploads WHERE blob_id=$1 AND object_key=$2 AND service_name=$3 AND state IN ('cancelled','expired','purged') LIMIT 1",
      [object["blob_id"], object["key"], object["service_name"]],
      log: false
    ).rows != []
  end
end
