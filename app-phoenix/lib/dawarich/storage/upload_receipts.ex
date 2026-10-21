defmodule Dawarich.Storage.UploadReceipts do
  @moduledoc false

  def bind!(repo, blob_id, user_id) when is_integer(user_id) or is_nil(user_id) do
    repo.query!(
      "INSERT INTO phoenix.upload_receipts(blob_id,user_id) VALUES($1,$2)",
      [blob_id, user_id],
      log: false
    )
  end

  def owned?(repo, blob_id, user_id) do
    repo.query!(
      "SELECT 1 FROM phoenix.upload_receipts r JOIN active_storage_blobs b ON b.id=r.blob_id WHERE r.blob_id=$1 AND r.user_id=$2",
      [blob_id, user_id],
      log: false
    ).rows == [[1]]
  end

  def owned_archive?(repo, blob_id, user_id) do
    owned?(repo, blob_id, user_id) or
      repo.query!(
        "SELECT 1 FROM active_storage_attachments a JOIN exports e ON e.id=a.record_id JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.record_type='Export' AND a.blob_id=$1 AND e.user_id=$2 FOR SHARE OF a,e,b",
        [blob_id, user_id],
        log: false
      ).rows != []
  end
end
