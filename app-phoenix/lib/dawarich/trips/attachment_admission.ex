defmodule Dawarich.Trips.AttachmentAdmission do
  @moduledoc false

  @embedded """
  SELECT blob_id FROM active_storage_attachments
  WHERE record_type='ActionText::RichText' AND name='embeds' AND record_id=$1 AND blob_id=ANY($2)
  """

  @receipts "SELECT blob_id, user_id FROM phoenix.upload_receipts WHERE blob_id=ANY($1)"

  def admit(_repo, _user_id, _rich, []), do: :ok

  def admit(repo, user_id, rich, ids) do
    embedded = if rich, do: repo.query!(@embedded, [rich, ids], log: false).rows, else: []
    embedded = MapSet.new(embedded, &hd/1)
    receipts = repo.query!(@receipts, [ids], log: false).rows

    foreign =
      Enum.any?(receipts, fn [blob, owner] ->
        owner != user_id and not MapSet.member?(embedded, blob)
      end)

    if foreign, do: {:error, :attachment_refused}, else: :ok
  end
end
