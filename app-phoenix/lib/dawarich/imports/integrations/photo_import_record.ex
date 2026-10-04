defmodule Dawarich.Imports.Integrations.PhotoImportRecord do
  @moduledoc false
  alias Dawarich.{Storage, Notifications, RailsCommands}
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.State.Lease
  alias DawarichWeb.Translate

  def run(repo, args, provider, source, fetch, opts) do
    lane = "command:imports.#{provider}_geodata"
    name = "#{provider}-geodata:#{args["user_id"]}"

    if Processed.done?(repo, args["event_id"]) do
      :ok
    else
      case Lease.with_lease(
             repo,
             name,
             fn holder ->
               context = %{
                 repo: repo,
                 args: args,
                 lane: lane,
                 lease: name,
                 holder: holder,
                 provider: provider,
                 source: source
               }

               case repo.transaction(fn -> user!(context) end) do
                 {:ok, user} -> produce(Map.merge(context, user), fetch, opts)
                 {:error, :lost} -> {:cancel, :ownership_lost}
               end
             end,
             timeout_ms: 0
           ) do
        {:ok, result} -> result
        {:error, :timeout} -> {:snooze, 5}
      end
    end
  end

  defp produce(ctx, fetch, opts) do
    case fetch.(ctx.settings, fn -> current?(ctx) end) do
      {:ok, []} -> finish_empty(ctx)
      {:ok, rows} -> publish(ctx, rows, opts)
      error -> error
    end
  end

  defp user!(ctx) do
    lease!(ctx)
    if Ownership.lock(ctx.repo, ctx.lane) != :oban, do: ctx.repo.rollback(:lost)

    [[stamp]] =
      ctx.repo.query!("SELECT updated_at FROM phoenix.job_owners WHERE key=$1", [ctx.lane],
        log: false
      ).rows

    case ctx.repo.query!(
           "SELECT email,settings,status,subscription_source FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
           [ctx.args["user_id"]],
           log: false
         ).rows do
      [[email, settings, status, sub]] ->
        %{email: email, settings: settings, status: status, sub: sub, stamp: stamp}

      _ ->
        ctx.repo.rollback(:lost)
    end
  end

  defp fence!(ctx) do
    current = user!(ctx)

    if current.stamp != ctx.stamp or current.settings != ctx.settings,
      do: ctx.repo.rollback(:lost)

    :ok
  end

  defp current?(ctx), do: match?({:ok, :ok}, ctx.repo.transaction(fn -> fence!(ctx) end))

  defp lease!(ctx) do
    case ctx.repo.query!(
           "SELECT holder,expires_at>statement_timestamp() FROM phoenix.leases WHERE name=$1 FOR UPDATE",
           [ctx.lease],
           log: false
         ).rows do
      [[holder, true]] when holder == ctx.holder -> :ok
      _ -> ctx.repo.rollback(:lost)
    end
  end

  defp finish_empty(ctx) do
    result =
      ctx.repo.transaction(fn ->
        fence!(ctx)
        Processed.mark!(ctx.repo, ctx.args["event_id"], ctx.lane)
      end)

    outcome(result)
  end

  defp publish(ctx, rows, opts) do
    zone = Dawarich.Imports.ZonePeriod.load!(Dawarich.TimeZoneName.to_iana(ctx.args["time_zone"]))

    dates =
      Enum.map([hd(rows), List.last(rows)], fn {_, _, stamp} ->
        zone
        |> Dawarich.Imports.ZonePeriod.local_now(DateTime.from_unix!(stamp))
        |> NaiveDateTime.to_date()
        |> Date.to_iso8601()
      end)

    [from, to] = dates
    name = "#{ctx.provider}-geodata-#{ctx.email}-from-#{from}-to-#{to}.json"
    storage = Keyword.get_lazy(opts, :storage, &Dawarich.Imports.StorageContext.storage/0)
    directory = Storage.tmp_dir!(storage, ctx.args["event_id"])

    try do
      File.write!(Path.join(directory, "photos.json"), encode(rows))

      if current?(ctx) do
        blob =
          Storage.put!(storage, Path.join(directory, "photos.json"), name, "application/json")

        result =
          try do
            ctx.repo.transaction(fn -> insert!(ctx, name, blob, storage) end)
          rescue
            error ->
              Storage.delete(storage, blob.key)
              reraise error, __STACKTRACE__
          end

        if result != {:ok, :created}, do: Storage.delete(storage, blob.key)
        outcome(result)
      else
        {:cancel, :ownership_lost}
      end
    after
      File.rm_rf!(directory)
      File.rmdir(Path.dirname(directory))
    end
  end

  defp insert!(ctx, name, blob, storage) do
    fence!(ctx)
    owner = Ownership.lock(ctx.repo, "command:imports.process_normal")

    existing =
      ctx.repo.query!(
        "SELECT source FROM imports WHERE user_id=$1 AND name=$2",
        [ctx.args["user_id"], name],
        log: false
      ).rows

    if existing != [] and existing != [[ctx.source]], do: ctx.repo.rollback(:name_conflict)

    if existing != [] do
      locale = ctx.settings["locale"] || "en"
      prefix = "services.#{ctx.provider}.import_geodata."
      title = Translate.t(locale, prefix <> "import_was_not_created", %{})

      content =
        Translate.t(
          locale,
          prefix <> "import_with_the_same_name_import_name_already_exists_if",
          %{import_name: name}
        )

      Notifications.create!(ctx.repo, ctx.args["user_id"], :info, title, content)
      Processed.mark!(ctx.repo, ctx.args["event_id"], ctx.lane)
      :duplicate
    else
      if ctx.status == 2 and ctx.sub in [nil, 0] and
           ctx.repo.query!(
             "SELECT count(*) FROM imports WHERE user_id=$1 AND demo=false",
             [ctx.args["user_id"]],
             log: false
           ).rows
           |> hd()
           |> hd() >= 5,
         do: ctx.repo.rollback(:quota)

      [[id]] =
        ctx.repo.query!(
          "INSERT INTO imports(user_id,name,source,additional_data_extraction_status,created_at,updated_at) VALUES($1,$2,$3,5,now(),now()) RETURNING id",
          [ctx.args["user_id"], name, ctx.source],
          log: false
        ).rows

      [[blob_id]] =
        ctx.repo.query!(
          "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,now()) RETURNING id",
          [
            blob.key,
            blob.filename,
            blob.content_type,
            blob.metadata,
            Map.get(storage, :stored_service, blob.service_name),
            blob.byte_size,
            blob.checksum
          ],
          log: false
        ).rows

      ctx.repo.query!(
        "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Import',$1,$2,now())",
        [id, blob_id],
        log: false
      )

      payload = %{
        "user_id" => ctx.args["user_id"],
        "import_id" => id,
        "time_zone" => ctx.args["time_zone"]
      }

      if owner == :oban do
        ctx.repo.query!(
          "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at) VALUES($1,'imports.process_normal',1,$2,$3,$4,$5,now())",
          [
            Ecto.UUID.dump!(Ecto.UUID.generate()),
            payload,
            %{"producer" => "Phoenix photo import"},
            id,
            "process-normal:#{id}"
          ],
          log: false
        )
      else
        RailsCommands.insert!(ctx.repo, "imports.upload_created", payload)
      end

      Processed.mark!(ctx.repo, ctx.args["event_id"], ctx.lane)
      :created
    end
  end

  defp outcome({:ok, _}), do: :ok
  defp outcome({:error, :lost}), do: {:cancel, :ownership_lost}
  defp outcome({:error, reason}), do: {:discard, reason}

  defp encode(rows) do
    items =
      Enum.map(rows, fn {lat, lon, timestamp} ->
        "{\"latitude\":#{Jason.encode!(lat)},\"longitude\":#{Jason.encode!(lon)},\"lonlat\":#{Jason.encode!("SRID=4326;POINT(#{lon} #{lat})")},\"timestamp\":#{timestamp}}"
      end)

    "[" <> Enum.join(items, ",") <> "]"
  end
end
