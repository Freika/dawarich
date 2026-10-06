defmodule Dawarich.Imports.Api do
  @moduledoc false
  alias Dawarich.{I18n, RubyInteger, Storage}
  alias Dawarich.Imports.UiRecords
  alias Dawarich.Jobs.Ownership

  @extensions ~w(.gpx .geojson .json .kml .kmz .rec .csv .tcx .fit .zip)
  @columns ~w(id name source status created_at points_count processed error_message)
  @statuses ~w(created processing completed failed deleting)

  def extensions, do: @extensions

  def index(repo, actor, params) do
    page = max(integer(params["page"]), 1)
    per = min(integer(Map.get(params, "per_page", 25)), 100)
    [[count]] = repo.query!("SELECT count(*) FROM imports WHERE user_id=$1", [actor]).rows
    if per == 0, do: raise(ArgumentError)
    per = if per < 0, do: 25, else: per

    rows =
      select(
        repo,
        actor,
        "WHERE user_id=$1 ORDER BY created_at DESC LIMIT $2 OFFSET $3",
        [actor, per, (page - 1) * per]
      )

    {:ok, Enum.map(rows, &serialize/1), %{current_page: page, total_pages: ceil(count / per)}}
  end

  defp integer(value) when is_nil(value) or is_number(value) or is_binary(value),
    do: RubyInteger.to_i(value)

  defp integer(_), do: raise(ArgumentError)

  def show(repo, actor, id) do
    id = RubyInteger.to_i(id)

    case select(repo, actor, "WHERE id=$1 AND user_id=$2", [id, actor]) do
      [row] -> {:ok, serialize(row)}
      [] -> error(404, "controllers.api.record_not_found")
    end
  end

  def context(conn) do
    Map.merge(
      %{
        self_hosted?: DawarichWeb.LayoutAssigns.self_hosted?(),
        now: DateTime.utc_now(),
        storage: Storage.config!(System.get_env())
      },
      conn.assigns[:api_context] || %{}
    )
  end

  def guard(user, ctx, points? \\ false, write? \\ true) do
    cond do
      is_nil(user) ->
        error(401, "controllers.api.user_account_is_not_active_or_has_been_deleted")

      user.status == 3 ->
        {:error, 402,
         %{
           "error" => "payment_required",
           "message" => I18n.en!("controllers.api.complete_your_subscription_to_continue"),
           "resume_url" => upgrade(user, ctx)
         }}

      user.status == 0 ->
        error(401, "controllers.api.user_account_is_not_active")

      expired?(user.active_until, ctx.now) ->
        error(401, "controllers.api.user_subscription_is_not_active")

      write? and not Dawarich.Entitlements.full_access?(user, ctx.self_hosted?, ctx.now) ->
        {:error, 403,
         %{
           "error" => "write_api_restricted",
           "message" =>
             I18n.en!("controllers.api.write_api_access_requires_a_pro_plan_your_data_was"),
           "upgrade_url" => upgrade(user, ctx)
         }}

      points? and not ctx.self_hosted? and Dawarich.Ingest.Closure.points_limit?(user) ->
        error(401, "controllers.api.points_limit_exceeded")

      true ->
        :ok
    end
  end

  def create(repo, user, params, ctx) do
    with :ok <- guard(user, ctx, true),
         {:ok, file} <- file(params),
         :ok <- file_type(file),
         :ok <- trial(repo, user, file) do
      store_import(repo, user, file, ctx)
    end
  rescue
    _ -> error(500, "controllers.api.v1.imports.an_error_occurred_while_processing_the_import")
  end

  def file(%{"file" => %Plug.Upload{} = upload}), do: {:ok, upload}
  def file(_), do: error(422, "controllers.api.v1.imports.missing_required_parameter_file")

  defp file_type(file) do
    ext = file.filename |> Path.extname() |> String.downcase()

    if ext in @extensions,
      do: :ok,
      else:
        error(422, "controllers.api.v1.imports.unsupported_file_type_ext_allowed_join",
          ext: ext,
          allowed: Enum.join(@extensions, ", ")
        )
  end

  def trial(repo, user, file) do
    if user.status == 2 and user.subscription_source in [nil, 0] do
      [[count]] =
        repo.query!("SELECT count(*) FROM imports WHERE user_id=$1 AND demo=false", [user.id]).rows

      cond do
        File.stat!(file.path).size > 11 * 1024 * 1024 ->
          {:error, 422,
           %{
             "error" =>
               "File " <>
                 I18n.en!("models.import.is_too_large_trial_users_can_only_upload_files_up")
           }}

        count >= 5 ->
          error(422, "models.import.trial_users_can_only_create_up_to_5_imports_please")

        true ->
          :ok
      end
    else
      :ok
    end
  end

  defp store_import(repo, user, file, ctx) do
    name = unique_name(repo, user.id, file.filename, ctx.now)

    with :ok <- Dawarich.PendingImports.Claim.available(repo, user.id, name),
         {:ok, {id, blob}} <-
           repo.transaction(fn ->
             blob = blob(repo, "Import", 0, file, ctx, mime(file.filename))
             blob_id = blob.id

             repo.query!(
               "DELETE FROM active_storage_attachments WHERE record_type='Import' AND record_id=0 AND blob_id=$1",
               [blob_id]
             )

             [[id]] =
               repo.query!(
                 "INSERT INTO imports(user_id,name,status,additional_data_extraction_status,created_at,updated_at) VALUES($1,$2,0,5,$3,$3) RETURNING id",
                 [user.id, name, DateTime.to_naive(ctx.now)]
               ).rows

             repo.query!(
               "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Import',$1,$2,$3)",
               [id, blob.id, DateTime.to_naive(ctx.now)]
             )

             {id, blob}
           end) do
      upload(blob, file, ctx)

      {:ok, _} =
        repo.transaction(fn ->
          Dawarich.PendingImports.Claim.enqueue(
            repo,
            user,
            id,
            Ownership.lock(repo, "command:imports.process_normal")
          )
        end)

      Map.get(ctx, :after_commit, fn -> :ok end).()
      {:ok, record} = show(repo, user.id, id)
      {:ok, 201, record}
    else
      {:error, reason} -> {:error, 422, %{"error" => to_string(reason)}}
    end
  end

  def attach(repo, type, record, file, ctx, content_type) do
    blob = blob(repo, type, record, file, ctx, content_type)
    upload(blob, file, ctx)
    blob
  end

  def blob(repo, type, record, file, ctx, content_type) do
    {checksum, size} = Storage.digest_file!(file.path)

    blob = %{
      key: Storage.generate_key(),
      filename: file.filename,
      byte_size: size,
      checksum: checksum,
      content_type: content_type,
      metadata: ~s({"identified":true,"analyzed":true}),
      service_name: ctx.storage.service
    }

    id = Dawarich.Storage.Blobs.attach!(repo, type, record, blob, DateTime.to_naive(ctx.now))
    Map.put(blob, :id, id)
  end

  def upload(blob, file, ctx) do
    path = Path.join(System.tmp_dir!(), "a12f2e-" <> Storage.generate_key())
    File.cp!(file.path, path)

    try do
      Storage.put!(ctx.storage, path, file.filename, blob.content_type, blob.key)
    after
      File.rm(path)
    end
  end

  def unique_name(repo, actor, name, now) do
    [[settings]] = repo.query!("SELECT settings FROM users WHERE id=$1", [actor]).rows

    [[stamp]] =
      Dawarich.UserTimeZone.query!(
        "SELECT to_char($1::timestamp AT TIME ZONE 'UTC' AT TIME ZONE z.name,'YYYYMMDD_HH24MISS') FROM z",
        [DateTime.to_naive(now)],
        settings,
        repo
      ).rows

    if repo.query!("SELECT 1 FROM imports WHERE user_id=$1 AND name=$2", [actor, name]).rows == [],
      do: name,
      else:
        Path.rootname(name) <>
          "_" <> stamp <> Path.extname(name)
  end

  defp mime(name), do: MIME.from_path(name)

  defp serialize(row) do
    record = Map.new(Enum.zip(@columns, row))

    record
    |> Map.update!("source", &if(is_nil(&1), do: nil, else: Enum.at(UiRecords.sources(), &1)))
    |> Map.update!("status", &Enum.at(@statuses, &1))
  end

  def term(record) when is_map(record), do: {:object, Enum.map(@columns, &{&1, record[&1]})}
  def term(records) when is_list(records), do: Enum.map(records, &term/1)

  defp select(repo, actor, where, params) do
    settings =
      case repo.query!("SELECT settings FROM users WHERE id=$1", [actor]).rows do
        [[settings]] -> settings || %{}
        _ -> %{}
      end

    zone = Dawarich.UserTimeZone.name(settings, repo)

    {:ok, rows} =
      repo.transaction(fn ->
        repo.query!("SELECT set_config('TimeZone',$1,true)", [zone])

        columns =
          Enum.map_join(@columns, ",", fn
            "created_at" -> Dawarich.RailsTime.sql("created_at", 3)
            column -> column
          end)

        repo.query!("SELECT #{columns} FROM imports #{where}", params).rows
      end)

    rows
  end

  def error(status, key, opts \\ []) do
    {:ok, message} = I18n.t("en", key, Map.new(opts, fn {k, v} -> {to_string(k), v} end))
    {:error, status, %{"error" => message}}
  end

  defp upgrade(_user, %{self_hosted?: true}), do: nil
  defp upgrade(user, ctx), do: Dawarich.SubscriptionToken.url(user, ctx.now)
  defp expired?(nil, _now), do: false

  defp expired?(%NaiveDateTime{} = until, now),
    do: NaiveDateTime.compare(until, DateTime.to_naive(now)) == :lt

  defp expired?(%DateTime{} = until, now), do: DateTime.compare(until, now) == :lt
end
