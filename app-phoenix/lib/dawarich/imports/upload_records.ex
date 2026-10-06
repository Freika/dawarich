defmodule Dawarich.Imports.UploadRecords do
  @moduledoc false
  alias Dawarich.RailsCommands

  def insert!(repo, user, item, owner) do
    blob = item.blob
    owner = if Dawarich.Standalone.enabled?(), do: :oban, else: owner

    locked =
      repo.query!(
        "SELECT metadata FROM public.active_storage_blobs WHERE id=$1 FOR UPDATE",
        [blob.id],
        log: false
      ).rows

    unless locked != [], do: repo.rollback(:not_found)
    if trial?(user) and blob.byte_size > 11 * 1024 * 1024, do: repo.rollback(:file_too_large)

    if repo.query!(
         "SELECT 1 FROM public.active_storage_attachments WHERE blob_id=$1 LIMIT 1",
         [blob.id],
         log: false
       ).rows != [],
       do: repo.rollback(:already_attached)

    name = unique_name(repo, user, item.name)
    extraction = if item.source in [0, 3, 4, 13], do: 0, else: 5

    [[id]] =
      repo.query!(
        "INSERT INTO public.imports(user_id,name,source,status,additional_data_extraction_status,created_at,updated_at) VALUES($1,$2,$3,0,$4,now(),now()) RETURNING id",
        [user.id, name, item.source, extraction],
        log: false
      ).rows

    repo.query!(
      "INSERT INTO public.active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Import',$1,$2,now())",
      [id, blob.id],
      log: false
    )

    repo.query!(
      "UPDATE public.active_storage_blobs SET metadata=$2 WHERE id=$1",
      [blob.id, Jason.encode!(item.metadata)],
      log: false
    )

    zone = captured_zone(user, repo)
    payload = %{"import_id" => id, "user_id" => user.id, "time_zone" => zone}

    cond do
      item.source == 8 ->
        Dawarich.UserData.ImportCommands.enqueue(repo, %{id: id, user_id: user.id}, %{
          zone: zone,
          locale: Dawarich.Mail.ExploreFeatures.locale(user.settings, nil) || "en"
        })

      owner == :oban ->
        type = if item.source == 4, do: "imports.process_gpx", else: "imports.process_normal"
        lane = if item.source == 4, do: "gpx", else: "normal"

        repo.query!(
          "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at) VALUES(gen_random_uuid(),$1,1,$2,$3,$4,$5,now())",
          [type, payload, %{"producer" => "Phoenix ImportsCreate"}, id, "process-#{lane}:#{id}"],
          log: false
        )

      true ->
        RailsCommands.insert!(repo, "imports.upload_created", payload)
    end

    id
  end

  defp captured_zone(user, repo) do
    zone = Map.get(user.settings, "timezone") || System.get_env("TIME_ZONE", "UTC")
    Dawarich.Imports.ZonePeriod.load!(Dawarich.TimeZoneName.to_iana(zone))
    zone
  rescue
    _ in [ArgumentError, File.Error] -> Dawarich.UserTimeZone.name(user.settings, repo)
  end

  defp unique_name(repo, user, name) do
    if repo.query!(
         "SELECT 1 FROM public.imports WHERE user_id=$1 AND name=$2 LIMIT 1",
         [user.id, name],
         log: false
       ).rows == [] do
      name
    else
      extension = Path.extname(name)

      [[stamp]] =
        Dawarich.UserTimeZone.query!(
          "SELECT to_char(now() AT TIME ZONE z.name,'YYYYMMDD_HH24MISS') FROM z",
          [],
          user.settings,
          repo
        ).rows

      candidate = Path.rootname(name) <> "_" <> stamp <> extension

      if repo.query!(
           "SELECT 1 FROM public.imports WHERE user_id=$1 AND name=$2 LIMIT 1",
           [user.id, candidate],
           log: false
         ).rows != [],
         do: repo.rollback(:duplicate_name)

      candidate
    end
  end

  defp trial?(user), do: user.status == 2 and user.subscription_source in [nil, 0]
end
