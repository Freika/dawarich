defmodule Dawarich.Exports.Delete do
  @moduledoc false

  def call(repo, user_id, id, opts \\ []) do
    with {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 <- Integer.parse(to_string(id)) do
      repo.transaction(fn ->
        {url, type} =
          case repo.query!(
                 "SELECT e.id,e.url,e.file_type FROM public.exports e JOIN public.users u ON u.id=e.user_id WHERE e.id=$1 AND e.user_id=$2 AND u.deleted_at IS NULL FOR UPDATE OF e FOR SHARE OF u",
                 [id, user_id],
                 log: false
               ).rows do
            [[^id, url, type]] ->
              if is_binary(url) and String.trim(url) != "" do
                unless opts[:native], do: repo.rollback(:legacy_file)

                case Dawarich.Exports.LegacyPurgeWorker.path(url) do
                  {:ok, _} -> :ok
                  {:error, reason} -> repo.rollback(reason)
                end

                {url, type}
              else
                {nil, type}
              end

            _ ->
              repo.rollback(:not_found)
          end

        key = if type == 0, do: "command:exports.points", else: "command:users.export_data"

        native_owner =
          if opts[:native] do
            owner = Dawarich.Imports.NativeOwnership.lock(repo, key)
            unless owner == :oban, do: repo.rollback(:not_owned)
            owner
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
          owner = native_owner || Dawarich.Jobs.Ownership.lock(repo, key)

          if Dawarich.Standalone.enabled?() or owner == :oban do
            Dawarich.Exports.PurgeWorker.enqueue_export!(repo, blobs)
          else
            Dawarich.RailsCommands.insert!(repo, "exports.purge", %{
              "export_id" => id,
              "user_id" => user_id,
              "blob_ids" => blobs
            })
          end
        end

        if url, do: Dawarich.Exports.LegacyPurgeWorker.enqueue!(repo, id, user_id, url)

        if Dawarich.Exports.Events.native?(repo, type),
          do: Dawarich.Exports.Events.enqueue(repo, user_id, Ecto.UUID.generate(), :deleted)

        :deleted
      end)
    else
      _ -> {:error, :not_found}
    end
  end
end
