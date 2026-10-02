defmodule Dawarich.Imports.DestroyRecovery do
  @moduledoc false

  def receipt!(repo, id, user) do
    case repo.query!(
           "SELECT user_id,event_id,phase,context FROM phoenix.import_destroy_runs WHERE import_id=$1 FOR UPDATE",
           [id],
           log: false
         ).rows do
      [] ->
        nil

      [[^user, event, phase, context]] when phase != "removed" ->
        %{event: event, context: context}

      _ ->
        repo.rollback(:not_found)
    end
  end

  def active?(repo, id, user, receipt) do
    event = if receipt, do: Ecto.UUID.load!(receipt.event), else: nil

    [[queued]] =
      repo.query!(
        "SELECT EXISTS(SELECT 1 FROM job_outbox WHERE state='pending' AND command_type='imports.destroy' AND command_version=1 AND payload=jsonb_build_object('import_id',$1::bigint,'user_id',$2::bigint) AND event_id::text=$3) OR EXISTS(SELECT 1 FROM phoenix.rails_commands WHERE kind='imports.destroy_requested' AND payload=jsonb_build_object('import_id',$1::bigint,'user_id',$2::bigint,'event_id',$3::text))",
        [id, user, event],
        log: false
      ).rows

    queued or native_active?(repo, id, user, event) or (receipt != nil and running?(repo, id))
  end

  def supersede!(repo, id, user) do
    repo.query!(
      "UPDATE job_outbox SET state='quarantined',error_code='superseded_destroy' WHERE state='pending' AND command_type='imports.destroy' AND payload=jsonb_build_object('import_id',$1::bigint,'user_id',$2::bigint)",
      [id, user],
      log: false
    )
  end

  defp native_active?(repo, id, user, event) do
    [[installed]] =
      repo.query!("SELECT to_regclass('oban.oban_jobs') IS NOT NULL", [], log: false).rows

    if installed do
      [[active]] =
        repo.query!(
          "SELECT EXISTS(SELECT 1 FROM oban.oban_jobs WHERE worker='Dawarich.Imports.DestroyWorker' AND state IN ('available','scheduled','retryable','executing') AND args->>'import_id'=$1::bigint::text AND args->>'user_id'=$2::bigint::text AND ($3::text IS NULL OR args->>'event_id'=$3))",
          [id, user, event],
          log: false
        ).rows

      active
    else
      false
    end
  end

  defp running?(repo, id) do
    [[locked]] =
      repo.query!(
        "SELECT pg_try_advisory_xact_lock(hashtextextended($1,0))",
        ["phoenix-import:#{id}"],
        log: false
      ).rows

    not locked
  end
end
