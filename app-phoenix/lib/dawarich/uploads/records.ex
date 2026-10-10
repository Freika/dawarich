defmodule Dawarich.Uploads.Records do
  @moduledoc false
  alias Dawarich.Accounts.NativeAccess
  alias Dawarich.Storage.NativePurge

  @select "reference,user_id,blob_id,kind,state,original_filename,original_size,client_wrapped,expires_at,target_until"
  @columns ~w(reference user_id blob_id kind state original_filename original_size client_wrapped expires_at target_until)a

  def actor!(repo, scope) do
    id = scope && scope.user && scope.user.id
    repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [id], log: false)

    case NativeAccess.admit(scope, repo) do
      {:ok, current} -> current
      {:error, reason} -> repo.rollback(reason)
    end
  end

  def read(repo, ref, owner, lock \\ false) do
    if is_binary(ref) and byte_size(ref) <= 64 do
      suffix = if lock, do: " FOR UPDATE", else: ""

      case repo.query!(
             "SELECT #{@select} FROM phoenix.native_uploads WHERE reference=$1 AND user_id=$2" <>
               suffix,
             [ref, owner], log: false).rows do
        [row] -> Map.new(Enum.zip(@columns, row))
        _ -> nil
      end
    end
  end

  def pending!(repo, row) do
    cond do
      is_nil(row) ->
        repo.rollback(:not_found)

      row.state != "pending" ->
        repo.rollback(String.to_existing_atom(row.state))

      NaiveDateTime.compare(row.expires_at, NaiveDateTime.utc_now()) != :gt ->
        repo.rollback(:expired)

      attached?(repo, row.blob_id) ->
        repo.rollback(:attached)

      not Dawarich.Storage.UploadReceipts.owned?(repo, row.blob_id, row.user_id) ->
        repo.rollback(:not_found)

      is_nil(Dawarich.Storage.Blobs.find(row.blob_id, repo)) ->
        repo.rollback(:not_found)

      true ->
        row
    end
  end

  def attached?(repo, id),
    do:
      repo.query!("SELECT 1 FROM active_storage_attachments WHERE blob_id=$1 LIMIT 1", [id],
        log: false
      ).rows != []

  def finish!(repo, row, state) do
    repo.query!(
      "UPDATE phoenix.native_uploads SET state=$2 WHERE reference=$1",
      [row.reference, state], log: false)

    :ok
  end

  def cancel!(repo, row, state) do
    objects = NativePurge.collect(repo, [row.blob_id])
    NativePurge.mark!(repo, objects)
    finish!(repo, row, state)

    repo.insert!(Dawarich.Uploads.CleanupWorker.new(%{"reference" => row.reference}),
      prefix: "oban"
    )

    :cancelled
  end
end
