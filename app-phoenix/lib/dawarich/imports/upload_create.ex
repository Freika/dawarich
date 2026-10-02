defmodule Dawarich.Imports.UploadCreate do
  @moduledoc false
  alias Dawarich.Imports.{Uploads, Tempfiles, GpxArchive}
  alias Dawarich.{Storage, RailsCommands}
  alias Dawarich.Jobs.Ownership

  def create(repo, user, files, context) when is_list(files) and files != [] do
    with {:ok, blobs} <- prepare(repo, user, files, context),
         true <- Enum.all?(blobs, &(&1.source == 4)) || {:error, :rails_format} do
      repo.transaction(fn ->
        owner = Ownership.lock(repo, "command:imports.process_gpx")
        current = user!(repo, user.id)
        admission!(repo, current, length(blobs), context)
        Enum.map(blobs, &insert!(repo, current, &1, owner))
      end)
    end
  end

  def create(_, _, _, _), do: {:error, :no_files}

  defp prepare(repo, user, files, context) do
    Enum.reduce_while(files, {:ok, []}, fn raw, {:ok, acc} ->
      descriptor = descriptor(raw)

      case Uploads.fetch(repo, user, descriptor["signed_id"]) do
        {:ok, blob} ->
          original = original(descriptor, blob.filename)
          metadata = blob.metadata

          metadata =
            if Map.has_key?(descriptor, "client_wrapped"),
              do:
                Map.put(metadata, "dawarich_client_wrapped", descriptor["client_wrapped"] == true),
              else: metadata

          metadata =
            if original,
              do: Map.put(metadata, "dawarich_original_filename", original),
              else: metadata

          name = original || blob.filename
          source = classify(blob, name, context)
          {:cont, {:ok, acc ++ [%{blob: blob, name: name, source: source, metadata: metadata}]}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp descriptor(value) when is_map(value), do: value

  defp descriptor(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, %{} = descriptor} -> descriptor
      _ -> %{"signed_id" => value}
    end
  end

  defp descriptor(_), do: %{}

  defp original(%{"client_wrapped" => true, "original_filename" => name}, filename)
       when is_binary(name) do
    if name != "" and Path.basename(name) == name and filename == name <> ".zip", do: name
  end

  defp original(_, _), do: nil

  defp classify(%{byte_size: 0}, _, _), do: nil

  defp classify(blob, name, context) do
    if String.downcase(Path.extname(name)) == ".gpx" do
      Tempfiles.with_files(fn adopt ->
        services =
          Map.get_lazy(context, :services, fn ->
            config = Map.fetch!(context, :storage)
            %{Map.get(config, :stored_service, config.service) => config}
          end)

        {:ok, config} = Storage.ImportServices.resolve(services, blob)
        path = Storage.Reader.download!(config, blob, on_verified: adopt)

        case GpxArchive.prepare!(path, on_verified: adopt) do
          {:gpx, gpx} ->
            file = File.open!(gpx, [:read, :binary])

            header =
              try do
                IO.binread(file, 1024)
              after
                File.close(file)
              end

            header =
              if is_binary(header), do: String.trim_leading(header, <<239, 187, 191>>), else: ""

            if String.trim_leading(header) |> String.starts_with?(["<?xml", "<gpx"]) and
                 String.contains?(header, "<gpx"),
               do: 4

          {:legacy, _} ->
            nil
        end
      end)
    end
  rescue
    _error -> nil
  end

  defp user!(repo, id) do
    case repo.query!(
           "SELECT id,status,subscription_source,active_until,points_count,settings FROM public.users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
           [id],
           log: false
         ).rows do
      [[id, status, subscription, active, count, settings]] ->
        %{
          id: id,
          status: status,
          subscription_source: subscription,
          active_until: active,
          points_count: count || 0,
          settings: settings || %{}
        }

      _ ->
        repo.rollback(:forbidden)
    end
  end

  defp admission!(repo, user, added, context) do
    unless Dawarich.Entitlements.future?(user.active_until, DateTime.utc_now()),
      do: repo.rollback(:inactive)

    if not context.self_hosted? and user.points_count >= 10_000_000,
      do: repo.rollback(:points_limit)

    if trial?(user) do
      [[count]] =
        repo.query!(
          "SELECT count(*) FROM public.imports WHERE user_id=$1 AND demo=false",
          [user.id],
          log: false
        ).rows

      if count + added > 5, do: repo.rollback(:import_limit)
    end
  end

  defp insert!(repo, user, item, owner) do
    blob = item.blob

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
    extraction = if item.source == 4, do: 0, else: 5

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

    if owner == :oban and item.source == 4 do
      repo.query!(
        "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at) VALUES(gen_random_uuid(),'imports.process_gpx',1,$1,$2,$3,$4,now())",
        [payload, %{"producer" => "Phoenix ImportsCreate"}, id, "process-gpx:#{id}"],
        log: false
      )
    else
      RailsCommands.insert!(repo, "imports.upload_created", payload)
    end

    id
  end

  defp captured_zone(user, repo) do
    zone = Map.get(user.settings, "timezone") || System.get_env("TIME_ZONE", "UTC")
    Dawarich.Imports.ZonePeriod.load!(Dawarich.TimeZoneName.to_iana(zone))
    zone
  rescue
    ArgumentError -> Dawarich.UserTimeZone.name(user.settings, repo)
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
