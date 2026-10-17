defmodule Dawarich.RouteVideos.Scoped do
  @moduledoc false

  alias Dawarich.{MapGallery, Maps, RailsMessages, Repo, Storage}
  alias Dawarich.{TimeZoneName, UserSettings, UserTimeZone}
  alias Dawarich.RouteVideos.{AttachmentEffects, Retention, Writes}
  alias Dawarich.Storage.{Blobs, UploadReceipts}

  @ceiling 250 * 1024 * 1024
  @checksum ~r/\A[A-Za-z0-9+\/]{22}==\z/

  def reserve_upload(scope, attrs, opts \\ []) do
    admitted(scope, opts, fn actor ->
      if acceptable?(attrs) do
        storage = Storage.services!(System.get_env())

        Blobs.create_before_direct_upload(
          Storage.service!(storage, storage.default),
          %{
            "filename" => attrs["filename"],
            "byte_size" => attrs["byte_size"],
            "checksum" => attrs["checksum"],
            "content_type" => "video/mp4",
            "metadata" => nil
          },
          DateTime.to_naive(now(opts)),
          user_id: actor.id
        )
      else
        {:error, :rejected}
      end
    end)
  end

  def create_video(scope, %{"signed_id" => signed} = attrs, opts) when is_binary(signed) do
    repo = Keyword.get(opts, :repo, Repo)

    admitted(scope, opts, fn actor ->
      with {:ok, _blob} <- owned(repo, signed, actor.id, opts) do
        params = %{
          "route_video" => %{
            "file" => signed,
            "name" => text(attrs["name"]),
            "settings" => settings(attrs["settings"])
          }
        }

        repo
        |> Writes.create(actor, params, now(opts), scope.locale || "en", policy(opts),
          fresh: true
        )
        |> created()
      end
    end)
  end

  def create_video(_scope, _attrs, _opts), do: {:error, :invalid_upload}

  def discard_upload(scope, signed, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    admitted(scope, opts, fn actor ->
      with {:ok, blob} <- owned(repo, signed, actor.id, opts) do
        {:ok, :ok} =
          repo.transaction(fn ->
            AttachmentEffects.cleanup_failed_save!(repo, actor.id, blob)
            :ok
          end)

        :ok
      end
    end)
  end

  def destroy_video(scope, id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    admitted(scope, opts, fn actor ->
      case ident(id) do
        nil -> {:error, :not_found}
        id -> destroyed(Writes.destroy(repo, actor.id, id, now(opts)), id)
      end
    end)
  end

  def gallery(scope, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    admitted(scope, opts, fn actor ->
      with {:ok, zone} <- zone(repo, UserSettings.get(actor)),
           do: {:ok, MapGallery.route_videos(actor.id, zone)}
    end)
  end

  def zone(repo, %{"timezone" => name} = settings) when is_binary(name),
    do: known_zone(repo, settings)

  def zone(repo, %{} = settings) when not is_map_key(settings, "timezone"),
    do: known_zone(repo, settings)

  def zone(_repo, _settings), do: {:error, :invalid_zone}

  defp known_zone(repo, settings) do
    name = UserTimeZone.zone(settings, System.get_env()) |> TimeZoneName.to_iana()

    if Dawarich.TimeZoneNames.member?(repo, name),
      do: {:ok, name},
      else: {:error, :invalid_zone}
  end

  defp admitted(scope, opts, effect), do: Maps.with_actor(scope, effect, opts)

  defp acceptable?(attrs) do
    attrs["content_type"] == "video/mp4" and is_integer(attrs["byte_size"]) and
      attrs["byte_size"] in 1..@ceiling and is_binary(attrs["checksum"]) and
      attrs["checksum"] =~ @checksum and is_binary(attrs["filename"]) and
      String.valid?(attrs["filename"]) and attrs["filename"] != ""
  end

  defp owned(repo, signed, user_id, opts) when is_binary(signed) do
    with {:ok, blob} <- RailsMessages.verified_blob_id(signed, now(opts)),
         true <- UploadReceipts.owned?(repo, blob, user_id) do
      {:ok, blob}
    else
      _ -> {:error, :foreign_upload}
    end
  end

  defp owned(_repo, _signed, _user_id, _opts), do: {:error, :foreign_upload}

  defp created({:ok, %{id: _id, evicted: _evicted} = result}), do: {:ok, result}
  defp created({:error, %{phase: :rejected}}), do: {:error, :rejected}
  defp created({:error, %{phase: :invalid_signature}}), do: {:error, :invalid_upload}
  defp created({:error, _}), do: {:error, :failed}
  defp created({:replay, _}), do: {:error, :unavailable}

  defp destroyed({:ok, id}, id), do: {:ok, id}
  defp destroyed({:replay, _}, _id), do: {:error, :not_found}
  defp destroyed({:error, :not_found}, _id), do: {:error, :not_found}
  defp destroyed({:error, _}, _id), do: {:error, :failed}

  defp text(value) when is_binary(value), do: value
  defp text(_), do: ""

  defp settings(%{} = settings),
    do: Map.new(settings, fn {key, value} -> {to_string(key), to_string(value)} end)

  defp settings(_), do: %{}

  defp policy(opts),
    do: Keyword.get_lazy(opts, :policy, fn -> Retention.policy(System.get_env()) end)

  defp now(opts), do: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

  defp ident(id) when is_integer(id) and id > 0, do: id

  defp ident(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> value
      _ -> nil
    end
  end

  defp ident(_), do: nil
end
