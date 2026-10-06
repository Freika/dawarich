defmodule Dawarich.Imports.Destroy do
  @moduledoc false
  alias Dawarich.Imports.NativeOwnership, as: Ownership
  alias Dawarich.RailsCommands

  def enqueue(repo, user_id, import_id, context) do
    case repo.transaction(fn ->
           owner = Ownership.lock(repo, "command:imports.destroy")

           user =
             repo.query!(
               "SELECT id FROM users WHERE id=$1 AND deleted_at IS NULL FOR SHARE",
               [user_id],
               log: false
             ).rows

           if user == [], do: repo.rollback(:not_found)

           case repo.query!(
                  "SELECT status FROM imports WHERE id=$1 AND user_id=$2 FOR UPDATE",
                  [import_id, user_id],
                  log: false
                ).rows do
             [] ->
               repo.rollback(:not_found)

             _ ->
               if Dawarich.Imports.DestroyLease.foreign?(repo, import_id, user_id),
                 do: repo.rollback(:not_found)

               receipt = Dawarich.Imports.DestroyRecovery.receipt!(repo, import_id, user_id)

               if Dawarich.Imports.DestroyRecovery.active?(repo, import_id, user_id, receipt) do
                 :queued
               else
                 event = Ecto.UUID.generate()
                 payload = %{"import_id" => import_id, "user_id" => user_id}
                 captured = %{"time_zone" => context.zone, "locale" => context.locale}

                 captured = Map.merge(captured, if(receipt, do: receipt.context, else: %{}))
                 Dawarich.Imports.DestroyRecovery.supersede!(repo, import_id, user_id)

                 repo.query!(
                   "INSERT INTO phoenix.import_destroy_runs(import_id,user_id,event_id,context) VALUES($1,$2,$3,$4) ON CONFLICT(import_id) DO UPDATE SET user_id=EXCLUDED.user_id,event_id=EXCLUDED.event_id,job_id=NULL,attempt=NULL,token=NULL,phase='requested',native_fallback=false,context=EXCLUDED.context,updated_at=now()",
                   [import_id, user_id, Ecto.UUID.dump!(event), captured],
                   log: false
                 )

                 repo.query!(
                   "UPDATE imports SET status=4,updated_at=now() WHERE id=$1 AND user_id=$2",
                   [import_id, user_id],
                   log: false
                 )

                 if owner == :oban do
                   repo.query!(
                     "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at) VALUES($1,'imports.destroy',1,$2,$3,$4,$5,now()) ON CONFLICT DO NOTHING",
                     [
                       Ecto.UUID.dump!(event),
                       payload,
                       %{"producer" => "Phoenix Imports::Destroy"},
                       import_id,
                       "destroy-import:#{import_id}"
                     ],
                     log: false
                   )
                 else
                   RailsCommands.insert!(
                     repo,
                     "imports.destroy_requested",
                     Map.put(payload, "event_id", event)
                   )
                 end

                 :queued
               end
           end
         end) do
      {:ok, :queued} ->
        Dawarich.Imports.Events.broadcast(user_id)
        {:ok, :queued}

      other ->
        other
    end
  end
end
