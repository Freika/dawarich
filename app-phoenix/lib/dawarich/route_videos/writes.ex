defmodule Dawarich.RouteVideos.Writes do
  @moduledoc false

  alias Dawarich.RailsMessages
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.RouteVideos.{AttachmentJob, Recipe, Retention}

  @ceiling 250 * 1024 * 1024

  def create(repo, user, %{"route_video" => %{} = params}, now, locale, policy) do
    with {:ok, recipe} <- Recipe.read(params["settings"]),
         {:ok, name} <- name(params["name"], locale),
         {:ok, blob_id} <- verified(params["file"], now),
         {:ok, blob} <- blob(repo, blob_id, user.id) do
      cond do
        blob.content_type != "video/mp4" or blob.byte_size > @ceiling ->
          refuse(repo, user.id, blob_id)

        not identified?(blob.metadata) and not native?(repo) ->
          {:replay, "blob identification or analysis requires Rails storage"}

        true ->
          save(repo, user.id, blob_id, name, recipe, now, policy)
      end
    end
  end

  def create(_repo, _user, _params, _now, _locale, _policy),
    do: {:replay, "route video shape"}

  defp name(value, locale) when is_nil(value) or is_binary(value) do
    if is_nil(value) or String.valid?(value) do
      {:ok,
       if(Ruby.blank?(value),
         do: DawarichWeb.Translate.t(locale, "controllers.route_videos.untitled", %{}),
         else: value
       )}
    else
      {:replay, "name encoding"}
    end
  end

  defp name(_value, _locale), do: {:replay, "name shape"}

  defp verified(signed, now) do
    case RailsMessages.verified_blob_id(signed, now) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, %{phase: :invalid_signature}}
    end
  end

  defp blob(repo, id, user_id, lock \\ "") do
    case repo.query!(
           """
           SELECT content_type,byte_size,metadata FROM active_storage_blobs b
           WHERE b.id=$1 AND NOT EXISTS (
             SELECT 1 FROM active_storage_attachments a
             LEFT JOIN route_videos v ON a.record_type='RouteVideo' AND v.id=a.record_id
             LEFT JOIN posters p ON a.record_type='Poster' AND p.id=a.record_id
             LEFT JOIN imports i ON a.record_type='Import' AND i.id=a.record_id
             LEFT JOIN exports e ON a.record_type='Export' AND e.id=a.record_id
             WHERE a.blob_id=b.id AND COALESCE(v.user_id,p.user_id,i.user_id,e.user_id,0)<>$2
           ) #{lock}
           """,
           [id, user_id],
           log: false
         ).rows do
      [[type, size, metadata]] ->
        if Dawarich.Storage.NativePurge.pending?(metadata),
          do: {:error, %{phase: :invalid_signature}},
          else: {:ok, %{content_type: type, byte_size: size, metadata: metadata}}

      [] ->
        {:error, %{phase: :invalid_signature}}
    end
  end

  defp identified?(metadata) when is_binary(metadata) do
    case Jason.decode(metadata) do
      {:ok, %{"identified" => true, "analyzed" => true}} -> true
      _ -> false
    end
  end

  defp identified?(_metadata), do: false

  defp refuse(repo, user_id, blob_id) do
    if attached?(repo, blob_id) do
      if Dawarich.Standalone.enabled?(),
        do: {:error, %{phase: :rejected}},
        else: {:replay, "rejected shared blob"}
    else
      repo.transaction(fn -> purge_unattached(repo, user_id, blob_id) end)
      {:error, %{phase: :rejected}}
    end
  end

  defp save(repo, user_id, blob_id, name, recipe, now, policy) do
    case insert(repo, user_id, blob_id, name, recipe, DateTime.to_naive(now)) do
      {:ok, id} ->
        cap(repo, user_id, id, policy.max_per_user, now)

      {:error, :admission_refused} ->
        {:error, %{phase: :invalid_signature}}

      {:error, _} ->
        repo.transaction(fn ->
          Dawarich.RouteVideos.AttachmentEffects.cleanup_failed_save!(repo, user_id, blob_id)
        end)

        {:error, %{phase: :pre_attach}}
    end
  end

  defp insert(repo, user_id, blob_id, name, recipe, now) do
    repo.transaction(fn ->
      repo.query!("SELECT id FROM active_storage_blobs WHERE id=$1 FOR UPDATE", [blob_id],
        log: false
      )

      case blob(repo, blob_id, user_id, "FOR UPDATE OF b") do
        {:ok, _} -> :ok
        {:error, _} -> repo.rollback(:admission_refused)
      end

      [[id]] =
        repo.query!(
          "INSERT INTO route_videos (user_id,name,status,settings,created_at,updated_at) VALUES ($1,$2,0,$3,$4,$4) RETURNING id",
          [user_id, name, recipe, now],
          log: false
        ).rows

      repo.query!(
        "INSERT INTO active_storage_attachments (name,record_type,record_id,blob_id,created_at) VALUES ('file','RouteVideo',$1,$2,$3)",
        [id, blob_id, now],
        log: false
      )

      if native?(repo),
        do: Dawarich.RouteVideos.AnalysisWorker.enqueue!(repo, user_id, id, blob_id)

      id
    end)
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError, RuntimeError] ->
      report(error, __STACKTRACE__)
      {:error, :save_failed}
  end

  defp native?(repo),
    do:
      Dawarich.Standalone.enabled?() or
        Dawarich.Jobs.Ownership.lock(repo, "cron:route_videos_purge_job") == :oban

  defp attached?(repo, blob_id),
    do:
      repo.query!(
        "SELECT EXISTS(SELECT 1 FROM active_storage_attachments WHERE blob_id=$1)",
        [blob_id],
        log: false
      ).rows == [[true]]

  defp purge_unattached(repo, user_id, blob_id),
    do:
      AttachmentJob.enqueue!(repo, %{
        "user_id" => user_id,
        "blob_id" => blob_id,
        "action" => "purge_unattached"
      })

  defp cap(_repo, _user_id, id, 0, _now), do: {:ok, %{id: id, evicted: []}}

  defp cap(repo, user_id, id, limit, now) do
    ids = Retention.expire_over_cap(repo, user_id, limit, now)
    {:ok, %{id: id, evicted: ids}}
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError, RuntimeError] ->
      report(error, __STACKTRACE__)
      {:error, %{phase: :post_commit, id: id}}
  end

  def detach(repo, user_id, id, now) do
    attachments =
      repo.query!(
        "SELECT id,blob_id FROM active_storage_attachments WHERE record_type='RouteVideo' AND record_id=$1 AND name='file' FOR UPDATE",
        [id],
        log: false
      ).rows

    for [attachment_id, blob_id] <- attachments do
      repo.query!("DELETE FROM active_storage_attachments WHERE id=$1", [attachment_id],
        log: false
      )

      repo.query!("UPDATE route_videos SET updated_at=$2 WHERE id=$1", [id, now], log: false)

      AttachmentJob.enqueue!(repo, %{
        "user_id" => user_id,
        "action" => "purge_detached",
        "blob_id" => blob_id,
        "attachment" => %{
          "id" => attachment_id,
          "name" => "file",
          "record_type" => "RouteVideo",
          "record_id" => id,
          "blob_id" => blob_id
        }
      })
    end
  end

  def destroy(repo, user_id, id, now) when is_integer(id) and id >= 0 do
    repo.transaction(fn ->
      case repo.query!(
             "SELECT id FROM route_videos WHERE id=$1 AND user_id=$2 FOR UPDATE",
             [id, user_id],
             log: false
           ).rows do
        [] ->
          if Dawarich.Standalone.enabled?(),
            do: {:error, :not_found},
            else: {:replay, "missing route video"}

        [[^id]] ->
          detach(repo, user_id, id, DateTime.to_naive(now))

          repo.query!("DELETE FROM route_videos WHERE id=$1 AND user_id=$2", [id, user_id],
            log: false
          )

          {:ok, id}
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  rescue
    _e in [Postgrex.Error, DBConnection.ConnectionError, RuntimeError] ->
      {:error, :destroy_failed}
  end

  def destroy(_repo, _user_id, _id, _now), do: {:replay, "route video id"}

  defp report(error, stack) do
    if Sentry.get_dsn(),
      do:
        Sentry.capture_exception(error,
          stacktrace: stack,
          handled: true,
          tags: %{"surface" => "route_videos"}
        )

    :ok
  rescue
    _ -> :ok
  end
end
