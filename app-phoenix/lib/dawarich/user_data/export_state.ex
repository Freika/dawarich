defmodule Dawarich.UserData.ExportState do
  @moduledoc false
  alias Dawarich.Jobs.{Ownership, Processed}
  @key "command:users.export_data"

  defmodule Lost do
    defexception message: "Backup export ownership lost"
  end

  def capture(repo, args, holder, now) do
    repo.transaction(fn ->
      if Ownership.lock(repo, @key) != :oban, do: repo.rollback(:lost)
      if Processed.done?(repo, args["event_id"]), do: repo.rollback(:done)

      case repo.query!(
             "SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
             [args["user_id"]],
             log: false
           ).rows do
        [] ->
          Processed.mark!(repo, args["event_id"], @key)
          :skip

        [[settings]] ->
          settings = Dawarich.UserSettings.safe(settings)

          [[stamp]] =
            repo.query!("SELECT updated_at FROM phoenix.job_owners WHERE key=$1", [@key],
              log: false
            ).rows

          uuid = Ecto.UUID.dump!(args["event_id"])

          existing =
            repo.query!(
              "SELECT e.id,e.name,e.status FROM exports e JOIN phoenix.export_claims c ON c.export_id=e.id WHERE c.event_id=$1 AND e.user_id=$2 ORDER BY e.id LIMIT 1 FOR UPDATE OF e",
              [uuid, args["user_id"]],
              log: false
            ).rows

          [id, name, status] =
            case existing do
              [row] ->
                row

              [] ->
                [[time]] =
                  repo.query!(
                    "SELECT to_char(($1::timestamp AT TIME ZONE 'UTC') AT TIME ZONE $2,'YYYYMMDD_HH24MISS')",
                    [now, Dawarich.TimeZoneName.to_iana(args["time_zone"])],
                    log: false
                  ).rows

                name = "user_data_export_#{time}.zip"

                [[id]] =
                  repo.query!(
                    "INSERT INTO exports(user_id,name,file_format,file_type,status,processing_started_at,created_at,updated_at) VALUES($1,$2,2,1,1,$3,$3,$3) RETURNING id",
                    [args["user_id"], name, now],
                    log: false
                  ).rows

                repo.query!(
                  "INSERT INTO phoenix.export_claims(export_id,event_id,claimed_at) VALUES($1,$2,$3)",
                  [id, uuid, DateTime.from_naive!(now, "Etc/UTC")],
                  log: false
                )

                [id, name, 1]
            end

          if status == 3, do: repo.rollback(:done)

          %{
            repo: repo,
            args: args,
            holder: holder,
            stamp: stamp,
            id: id,
            name: name,
            locale: settings["locale"] || "en",
            now: now
          }
      end
    end)
  end

  def effect!(state, fun) do
    case state.repo.transaction(fn ->
           fence!(state)
           fun.()
         end) do
      {:ok, result} -> result
      {:error, :lost} -> raise Lost
    end
  end

  def fence!(state) do
    repo = state.repo
    if Ownership.lock(repo, @key) != :oban, do: repo.rollback(:lost)

    [[stamp]] =
      repo.query!("SELECT updated_at FROM phoenix.job_owners WHERE key=$1", [@key], log: false).rows

    lease =
      repo.query!(
        "SELECT holder,expires_at>statement_timestamp() FROM phoenix.leases WHERE name=$1 FOR UPDATE",
        [lease_name(state.args)],
        log: false
      ).rows

    current =
      repo.query!(
        "SELECT e.status FROM exports e JOIN users u ON u.id=e.user_id JOIN phoenix.export_claims c ON c.export_id=e.id WHERE e.id=$1 AND e.user_id=$2 AND u.deleted_at IS NULL AND c.event_id=$3 FOR UPDATE OF e,u",
        [state.id, state.args["user_id"], Ecto.UUID.dump!(state.args["event_id"])],
        log: false
      ).rows

    if stamp != state.stamp or lease != [[state.holder, true]] or current not in [[[1]], [[2]]],
      do: repo.rollback(:lost)
  end

  def attach!(state, blob) do
    effect!(state, fn ->
      [[id]] =
        state.repo.query!(
          "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id",
          [
            blob.key,
            blob.filename,
            blob.content_type,
            blob.metadata,
            Map.get(blob, :stored_service, blob.service_name),
            blob.byte_size,
            blob.checksum,
            state.now
          ],
          log: false
        ).rows

      state.repo.query!(
        "UPDATE active_storage_attachments SET name='retired_file_' || id::text WHERE record_type='Export' AND record_id=$1 AND name='file'",
        [state.id],
        log: false
      )

      state.repo.query!(
        "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Export',$1,$2,$3)",
        [state.id, id, state.now],
        log: false
      )
    end)
  end

  def status!(state, code),
    do:
      effect!(state, fn ->
        state.repo.query!(
          "UPDATE exports SET status=$2,updated_at=$3 WHERE id=$1",
          [state.id, code, state.now],
          log: false
        )
      end)

  def fail!(state) do
    effect!(state, fn ->
      state.repo.query!(
        "UPDATE exports SET status=3,updated_at=$2 WHERE id=$1",
        [state.id, state.now],
        log: false
      )

      Processed.mark!(state.repo, state.args["event_id"], @key)
    end)
  end

  def finish!(state, fun),
    do:
      effect!(state, fn ->
        fun.()
        Processed.mark!(state.repo, state.args["event_id"], @key)
      end)

  def lease_name(args), do: "user-data-export:#{args["event_id"]}"
end
