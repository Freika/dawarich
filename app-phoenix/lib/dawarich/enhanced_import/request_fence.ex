defmodule Dawarich.EnhancedImport.RequestFence do
  @moduledoc false
  alias Dawarich.Jobs.Processed
  alias Dawarich.Imports.DestroyLock

  @fields ~w(import_id user_id source source_blob_id event_id started_at time_zone locale)

  def decode(payload, action) when is_map(payload) do
    fields = if action == :extract, do: ["lock_attempt" | @fields], else: @fields

    valid =
      Enum.sort(Map.keys(payload)) == Enum.sort(fields) and
        Enum.all?(~w(import_id user_id), &(is_integer(payload[&1]) and payload[&1] > 0)) and
        payload["source"] == 4 and
        (is_nil(payload["source_blob_id"]) or is_integer(payload["source_blob_id"])) and
        match?({:ok, _}, Ecto.UUID.cast(payload["event_id"])) and
        Enum.all?(~w(started_at time_zone locale), &is_binary(payload[&1])) and
        (action != :extract or
           (is_integer(payload["lock_attempt"]) and payload["lock_attempt"] >= 1))

    if valid, do: {:ok, payload}, else: {:error, "invalid_payload"}
  end

  def decode(_, _), do: {:error, "invalid_payload"}

  def run(repo, job, action, fun) do
    work = fn ->
      if Processed.done?(repo, job.args["event_id"]) do
        :ok
      else
        fence = fn effect, terminal -> effect!(repo, job, action, effect, terminal) end
        fence.(fn -> :ok end, false)
        fun.(fence)
      end
    end

    if job.id do
      case DestroyLock.run(repo, job.args["import_id"], work) do
        {:skip, :busy} -> {:snooze, 5}
        result -> result
      end
    else
      work.()
    end
  catch
    {:extraction_refused, reason} -> {:cancel, reason}
  end

  defp effect!(repo, job, action, fun, terminal) do
    case repo.transaction(fn ->
           check!(repo, job, action)
           result = fun.()

           if terminal and
                (action == :extract or
                   repo.query!(
                     "SELECT additional_data_extraction_status FROM imports WHERE id=$1",
                     [job.args["import_id"]],
                     log: false
                   ).rows == [[0]]),
              do: Processed.mark!(repo, job.args["event_id"], "enhanced_import.#{action}")

           result
         end) do
      {:ok, result} -> result
      {:error, reason} -> throw({:extraction_refused, reason})
    end
  end

  defp check!(repo, job, action) do
    args = job.args

    if job.id &&
         repo.query!(
           "SELECT state,attempt,worker,args FROM oban.oban_jobs WHERE id=$1 FOR SHARE",
           [job.id],
           log: false
         ).rows != [["executing", job.attempt, job.worker, args]],
       do: repo.rollback(:stale_attempt)

    current =
      repo.query!(
        "SELECT i.user_id,i.source,i.additional_data_extraction,i.additional_data_extraction_status FROM imports i JOIN users u ON u.id=i.user_id WHERE i.id=$1 AND i.status<>4 AND u.deleted_at IS NULL FOR UPDATE OF i FOR SHARE OF u",
        [args["import_id"]],
        log: false
      ).rows

    case current do
      [[user, source, data, status]] ->
        if Map.has_key?(args, "user_id") do
          expected_action = to_string(action)
          states = if action == :extract, do: [1, 2], else: [2, 4]

          unless user == args["user_id"] and source == args["source"] and status in states and
                   data["phoenix_extraction_event"] == args["event_id"] and
                   data["phoenix_extraction_action"] == expected_action and
                   data["started_at"] == args["started_at"],
                 do: repo.rollback(:changed_import)

          attachments =
            repo.query!(
              "SELECT blob_id FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1 AND name='file' FOR SHARE",
              [args["import_id"]],
              log: false
            ).rows

          if attachments != if(args["source_blob_id"], do: [[args["source_blob_id"]]], else: []),
            do: repo.rollback(:changed_source)

          if args["source_blob_id"] &&
               repo.query!(
                 "SELECT id FROM active_storage_blobs WHERE id=$1 FOR SHARE",
                 [args["source_blob_id"]],
                 log: false
               ).rows == [],
             do: repo.rollback(:changed_source)
        else
          if data["phoenix_extraction_event"], do: repo.rollback(:missing_request_identity)
        end

      [] ->
        repo.rollback(:changed_import)
    end
  end
end
