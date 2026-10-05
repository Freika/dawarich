defmodule Dawarich.Exports.Delete do
  @moduledoc false

  def call(repo, user_id, id) do
    with {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 <- Integer.parse(to_string(id)) do
      repo.transaction(fn ->
        case repo.query!(
               "SELECT e.id,e.url FROM public.exports e JOIN public.users u ON u.id=e.user_id WHERE e.id=$1 AND e.user_id=$2 AND u.deleted_at IS NULL FOR UPDATE OF e FOR SHARE OF u",
               [id, user_id],
               log: false
             ).rows do
          [[^id, url]] when url in [nil, ""] -> :ok
          [[^id, _]] -> repo.rollback(:legacy_file)
          _ -> repo.rollback(:not_found)
        end

        attachments =
          repo.query!(
            "SELECT id,blob_id FROM active_storage_attachments WHERE record_type='Export' AND record_id=$1 ORDER BY id FOR UPDATE",
            [id],
            log: false
          ).rows

        blobs = attachments |> Enum.map(&List.last/1) |> Enum.uniq() |> Enum.sort()

        repo.query!(
          "SELECT id FROM active_storage_blobs WHERE id=ANY($1) ORDER BY id FOR UPDATE",
          [blobs],
          log: false
        )

        repo.query!(
          "DELETE FROM active_storage_attachments WHERE record_type='Export' AND record_id=$1",
          [id],
          log: false
        )

        repo.query!("DELETE FROM exports WHERE id=$1 AND user_id=$2", [id, user_id], log: false)

        if blobs != [] do
          Dawarich.RailsCommands.insert!(repo, "exports.purge", %{
            "export_id" => id,
            "user_id" => user_id,
            "blob_ids" => blobs
          })
        end

        :deleted
      end)
    else
      _ -> {:error, :not_found}
    end
  end
end
