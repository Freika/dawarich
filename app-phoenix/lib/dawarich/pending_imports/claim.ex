defmodule Dawarich.PendingImports.Claim do
  @moduledoc false
  alias Dawarich.Imports.Api
  alias Dawarich.Jobs.Ownership

  def claim(user, ticket), do: claim(Dawarich.Repo, user, ticket, %{now: DateTime.utc_now()})

  def claim(repo, user, ticket, ctx) do
    with {:ok, ticket} <- Ecto.UUID.dump(ticket),
         {:ok, result} <- repo.transaction(fn -> convert(repo, user, ticket, ctx) end) do
      if result,
        do:
          repo.transaction(fn ->
            enqueue(
              repo,
              user,
              result["id"],
              Ownership.lock(repo, "command:imports.process_normal")
            )
          end)

      result
    else
      {:error, reason} -> {:error, reason}
      :error -> nil
    end
  end

  defp convert(repo, user, ticket, ctx) do
    case repo.query!(
           "UPDATE pending_imports SET claimed_at=$2,claimed_by_user_id=$3 WHERE claim_ticket=$1 AND claimed_at IS NULL AND expires_at>$2 RETURNING id,original_filename",
           [ticket, DateTime.to_naive(ctx.now), user.id]
         ).rows do
      [] ->
        nil

      [[pending, filename]] ->
        name = Api.unique_name(repo, user.id, filename, ctx.now)

        [[blob, size]] =
          repo.query!(
            "SELECT b.id,b.byte_size FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.record_type='PendingImport' AND a.record_id=$1 AND a.name='file' ORDER BY a.id LIMIT 1",
            [pending]
          ).rows

        validate!(repo, user, name, size)

        [[id]] =
          repo.query!(
            "INSERT INTO imports(user_id,name,status,additional_data_extraction_status,created_at,updated_at) VALUES($1,$2,0,5,$3,$3) RETURNING id",
            [user.id, name, DateTime.to_naive(ctx.now)]
          ).rows

        repo.query!(
          "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Import',$1,$2,$3)",
          [id, blob, DateTime.to_naive(ctx.now)]
        )

        {:ok, record} = Api.show(repo, user.id, id)
        record
    end
  end

  def enqueue(repo, user, id, owner) do
    payload = %{
      "import_id" => id,
      "user_id" => user.id,
      "time_zone" => Dawarich.UserTimeZone.name(user.settings, repo)
    }

    if owner == :oban do
      repo.query!(
        "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at) VALUES(gen_random_uuid(),'imports.process_normal',1,$1,$2,$3,$4,now())",
        [payload, %{"producer" => "Phoenix PendingImports Claim"}, id, "process-normal:#{id}"]
      )
    else
      Dawarich.RailsCommands.insert!(repo, "imports.upload_created", payload)
    end
  end

  def available(repo, actor, name) do
    cond do
      String.trim(name) == "" ->
        {:error, "Name can't be blank"}

      repo.query!("SELECT 1 FROM imports WHERE user_id=$1 AND name=$2", [actor, name]).rows != [] ->
        {:error, "Name has already been taken"}

      true ->
        :ok
    end
  end

  defp validate!(repo, user, name, size) do
    if String.trim(name) == "" or
         repo.query!("SELECT 1 FROM imports WHERE user_id=$1 AND name=$2", [user.id, name]).rows !=
           [],
       do: repo.rollback(:invalid_name)

    if user.status == 2 and user.subscription_source in [nil, 0] do
      [[count]] =
        repo.query!("SELECT count(*) FROM imports WHERE user_id=$1 AND demo=false", [user.id]).rows

      if count >= 5 or size > 11 * 1024 * 1024, do: repo.rollback(:trial_limit)
    end
  end
end
