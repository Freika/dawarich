defmodule Dawarich.RouteVideos.Writes do
  @moduledoc false

  alias Dawarich.{RailsCommands, RailsMessages}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.RouteVideos.Recipe

  @ceiling 250 * 1024 * 1024

  def create(repo, user, %{"route_video" => %{} = params}, now, locale, policy) do
    with {:ok, recipe} <- Recipe.read(params["settings"]),
         {:ok, name} <- name(params["name"], locale),
         {:ok, blob_id} <- verified(params["file"], now),
         {:ok, blob} <- blob(repo, blob_id) do
      cond do
        blob.content_type != "video/mp4" or blob.byte_size > @ceiling ->
          refuse(repo, user.id, blob_id)

        not identified?(blob.metadata) ->
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

  defp blob(repo, id) do
    case repo.query!(
           "SELECT content_type,byte_size,metadata FROM active_storage_blobs WHERE id=$1",
           [id],
           log: false
         ).rows do
      [[type, size, metadata]] ->
        {:ok, %{content_type: type, byte_size: size, metadata: metadata}}

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
      {:replay, "rejected shared blob"}
    else
      repo.transaction(fn -> purge_unattached(repo, user_id, blob_id) end)
      {:error, %{phase: :rejected}}
    end
  end

  defp save(repo, user_id, blob_id, name, recipe, now, policy) do
    case insert(repo, user_id, blob_id, name, recipe, DateTime.to_naive(now)) do
      {:ok, id} ->
        cap(repo, user_id, id, policy.max_per_user, DateTime.to_naive(now))

      {:error, _} ->
        repo.transaction(fn ->
          unless attached?(repo, blob_id), do: purge_unattached(repo, user_id, blob_id)
        end)

        {:error, %{phase: :pre_attach}}
    end
  end

  defp insert(repo, user_id, blob_id, name, recipe, now) do
    repo.transaction(fn ->
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

      id
    end)
  rescue
    _e in [Postgrex.Error, DBConnection.ConnectionError, RuntimeError] -> {:error, :save_failed}
  end

  defp attached?(repo, blob_id),
    do:
      repo.query!(
        "SELECT EXISTS(SELECT 1 FROM active_storage_attachments WHERE blob_id=$1)",
        [blob_id],
        log: false
      ).rows == [[true]]

  defp purge_unattached(repo, user_id, blob_id),
    do:
      RailsCommands.insert!(repo, "route_videos.attachment_job", %{
        "user_id" => user_id,
        "blob_id" => blob_id,
        "action" => "purge_unattached"
      })

  defp cap(_repo, _user_id, id, 0, _now), do: {:ok, %{id: id, evicted: []}}

  defp cap(repo, user_id, id, limit, now) do
    ids =
      repo.query!(
        "SELECT id FROM route_videos WHERE user_id=$1 AND status=0 ORDER BY created_at DESC,id DESC OFFSET $2",
        [user_id, limit],
        log: false
      ).rows
      |> List.flatten()

    Enum.each(ids, &expire(repo, user_id, &1, now))
    {:ok, %{id: id, evicted: ids}}
  rescue
    _e in [Postgrex.Error, DBConnection.ConnectionError, RuntimeError] ->
      {:error, %{phase: :post_commit, id: id}}
  end

  defp expire(repo, user_id, id, now) do
    repo.transaction(fn ->
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

        RailsCommands.insert!(repo, "route_videos.attachment_job", %{
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
    end)

    repo.query!(
      "UPDATE route_videos SET status=1,expired_at=$2,updated_at=$2 WHERE id=$1 AND status=0",
      [id, now],
      log: false
    )
  end
end
