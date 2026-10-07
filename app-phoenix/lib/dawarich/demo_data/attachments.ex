defmodule Dawarich.DemoData.Attachments do
  @moduledoc false

  def trip!(repo, user, id) do
    notes =
      repo.query!(
        "SELECT id FROM notes WHERE attachable_type='Trip' AND attachable_id=$1 AND user_id=$2 FOR UPDATE",
        [id, user],
        log: false
      ).rows
      |> List.flatten()

    rich_notes =
      repo.query!(
        "SELECT id FROM action_text_rich_texts WHERE record_type='Note' AND record_id=ANY($1) FOR UPDATE",
        [notes],
        log: false
      ).rows
      |> List.flatten()

    description =
      repo.query!(
        "SELECT id FROM action_text_rich_texts WHERE record_type='Trip' AND record_id=$1 AND name='description' FOR UPDATE",
        [id],
        log: false
      ).rows
      |> List.flatten()

    detach!(repo, "Trip", [id])
    detach!(repo, "Note", notes)
    detach!(repo, "ActionText::RichText", rich_notes ++ description)
    repo.query!("DELETE FROM action_text_rich_texts WHERE id=ANY($1)", [rich_notes], log: false)
  end

  def detach!(repo, type, ids) do
    blobs =
      repo.query!(
        "DELETE FROM active_storage_attachments WHERE record_type=$1 AND record_id=ANY($2) RETURNING blob_id",
        [type, ids],
        log: false
      ).rows
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.sort()

    Dawarich.Exports.PurgeWorker.enqueue!(repo, blobs)
  end
end
