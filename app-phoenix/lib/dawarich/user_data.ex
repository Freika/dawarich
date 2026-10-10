defmodule Dawarich.UserData do
  @moduledoc false

  alias Dawarich.Accounts.Scope
  alias Dawarich.Imports.Uploads
  alias Dawarich.Jobs.Ownership
  alias Dawarich.UserData.ImportCommands

  @legacy_trial_bytes 11 * 1024 * 1024
  @legacy_trial_imports 5

  def legacy_trial_too_large?(status, subscription, size),
    do: legacy_trial?(status, subscription) and size > @legacy_trial_bytes

  defp legacy_trial?(status, subscription), do: status == 2 and subscription in [nil, 0]

  def request_export(%Scope{user: user} = scope) do
    repo = repo()
    context = context(scope)

    {:ok, :ok} =
      repo.transaction(fn ->
        payload = %{"user_id" => user.id, "time_zone" => context.zone, "locale" => context.locale}

        if Ownership.lock(repo, "command:users.export_data") == :oban do
          repo.query!(
            "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES(gen_random_uuid(),'users.export_data',1,$1,$2,$3,now())",
            [payload, %{"producer" => "Phoenix SettingsUsersExport"}, user.id],
            log: false
          )
        else
          Dawarich.RailsCommands.insert!(repo, "users.export_data", payload)
        end

        :ok
      end)

    :ok
  end

  def start_import(%Scope{} = scope, value) do
    cond do
      Dawarich.Ingest.Ruby.blank?(value) -> {:error, :blank}
      not is_binary(value) -> {:error, :invalid_archive}
      true -> import_archive(scope, value)
    end
  end

  defp import_archive(%Scope{user: user} = scope, value) do
    repo = repo()
    context = context(scope)

    result =
      repo.transaction(fn ->
        Ownership.lock(repo, "command:users.import_data")

        [[status, subscription]] =
          repo.query!(
            "SELECT status,subscription_source FROM users WHERE id=$1 FOR UPDATE",
            [user.id],
            log: false
          ).rows

        with {:ok, blob} <- Uploads.fetch(repo, value),
             true <- Dawarich.Storage.UploadReceipts.owned_archive?(repo, blob.id, user.id),
             true <- zip?(blob) do
          if legacy_trial?(status, subscription) and
               (blob.byte_size > @legacy_trial_bytes or
                  trial_count(repo, user.id) >= @legacy_trial_imports),
             do: repo.rollback(:validation)

          name = unique_name(repo, user.id, blob.filename, context.zone)

          if String.trim(name) == "" or exists?(repo, user.id, name),
            do: repo.rollback(:validation)

          [[id]] =
            repo.query!(
              "INSERT INTO imports(user_id,name,source,status,additional_data_extraction_status,created_at,updated_at) VALUES($1,$2,8,0,5,now(),now()) RETURNING id",
              [user.id, name],
              log: false
            ).rows

          repo.query!(
            "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Import',$1,$2,now())",
            [id, blob.id],
            log: false
          )

          ImportCommands.enqueue(repo, %{id: id, user_id: user.id}, context)
        else
          _ -> repo.rollback(:invalid_archive)
        end
      end)

    case result do
      {:ok, _} -> :ok
      {:error, :validation} -> {:error, :validation}
      {:error, _} -> {:error, :invalid_archive}
    end
  rescue
    _ -> {:error, :invalid_archive}
  end

  def zip?(blob),
    do:
      blob.content_type in ["application/zip", "application/x-zip-compressed"] or
        String.downcase(Path.extname(blob.filename)) == ".zip"

  defp trial_count(repo, user) do
    [[count]] =
      repo.query!("SELECT count(*) FROM imports WHERE user_id=$1 AND demo=false", [user],
        log: false
      ).rows

    count
  end

  defp exists?(repo, user, name),
    do:
      repo.query!("SELECT 1 FROM imports WHERE user_id=$1 AND name=$2", [user, name], log: false).rows !=
        []

  defp unique_name(repo, user, name, zone) do
    if exists?(repo, user, name) do
      [[stamp]] =
        repo.query!(
          "SELECT to_char(now() AT TIME ZONE $1,'YYYYMMDD_HH24MISS')",
          [Dawarich.TimeZoneName.to_iana(zone)],
          log: false
        ).rows

      Path.rootname(Path.basename(name)) <> "_" <> stamp <> Path.extname(name)
    else
      name
    end
  end

  defp captured_zone(settings) do
    zone = settings["timezone"] || System.get_env("TIME_ZONE", "Europe/Berlin")
    Dawarich.Imports.ZonePeriod.load!(Dawarich.TimeZoneName.to_iana(zone))
    zone
  rescue
    _ -> Dawarich.UserTimeZone.name(settings, repo())
  end

  defp context(%Scope{user: user, locale: locale}),
    do: %{zone: captured_zone(Dawarich.UserSettings.get(user)), locale: locale}

  defp repo, do: Application.get_env(:dawarich, :imports_repo, Dawarich.Repo)
end
