defmodule Dawarich.Imports.Uploads do
  @moduledoc false
  alias Dawarich.Storage
  alias DawarichWeb.Endpoint

  @columns [:id, :key, :filename, :content_type, :metadata, :service_name, :byte_size, :checksum]
  @select "id,key,filename,content_type,metadata,service_name,byte_size,checksum"
  @extensions ~w(.json .geojson .gpx .kml .kmz .tcx .fit .csv .rec .zip .gz)

  def reserve(repo, user, attrs, config) when is_map(attrs) do
    with :ok <- admission(user, attrs),
         :ok <- valid(attrs) do
      metadata =
        Jason.encode!(%{"phoenix_import_owner" => user.id, "phoenix_import_uploaded" => false})

      [[id]] =
        repo.query!(
          "INSERT INTO public.active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES ($1,$2,$3,$4,$5,$6,$7,now()) RETURNING id",
          [
            Storage.generate_key(),
            attrs["filename"],
            attrs["content_type"],
            metadata,
            Map.get(config, :stored_service, config.service),
            attrs["byte_size"],
            attrs["checksum"]
          ],
          log: false
        ).rows

      {:ok,
       Map.merge(attrs, %{
         id: id,
         signed_id: sign("attachment", user.id, id),
         upload_token: sign("write", user.id, id)
       })}
    end
  end

  def reserve(_, _, _, _), do: {:error, :invalid_blob}

  def fetch(repo, user, token) do
    with {:ok, id} <- verify("attachment", user.id, token),
         {:ok, blob} <- owned(repo, user.id, id),
         true <- blob.metadata["phoenix_import_uploaded"] == true do
      {:ok, blob}
    else
      false -> {:error, :not_uploaded}
      {:error, :invalid_token} -> legacy_fetch(repo, user.id, token)
      error -> error
    end
  end

  defp legacy_fetch(repo, user_id, token) do
    with {:ok, id} <- Dawarich.Imports.RailsBlobReference.verify(token) do
      case repo.query!("SELECT #{@select} FROM public.active_storage_blobs WHERE id=$1", [id],
             log: false
           ).rows do
        [row] ->
          blob = Map.new(Enum.zip(@columns, row))

          metadata =
            case blob.metadata do
              value when is_map(value) ->
                value

              value when is_binary(value) ->
                case Jason.decode(value) do
                  {:ok, %{} = map} -> map
                  _ -> %{}
                end

              _ ->
                %{}
            end

          if metadata["phoenix_import_owner"] in [nil, user_id],
            do: {:ok, %{blob | metadata: metadata}},
            else: {:error, :forbidden}

        _ ->
          {:error, :not_found}
      end
    end
  end

  def upload_info(repo, user, token) do
    with {:ok, id} <- verify("write", user.id, token), do: owned(repo, user.id, id)
  end

  def write(repo, user, token, path, config) do
    with {:ok, id} <- verify("write", user.id, token),
         {:ok, blob} <- owned(repo, user.id, id) do
      repo.checkout(fn ->
        key = "phoenix-upload:#{id}"

        if repo.query!("SELECT pg_try_advisory_lock(hashtextextended($1,0))", [key], log: false).rows ==
             [[true]] do
          try do
            verified_write(repo, user, id, path, config, blob)
          after
            repo.query!("SELECT pg_advisory_unlock(hashtextextended($1,0))", [key], log: false)
          end
        else
          {:error, :busy}
        end
      end)
    end
  end

  defp verified_write(repo, user, id, path, config, blob) do
    {checksum, size} = Storage.digest_file!(path)

    cond do
      size != blob.byte_size or checksum != blob.checksum ->
        {:error, :integrity}

      Map.get(config, :stored_service, config.service) != blob.service_name ->
        {:error, :service}

      true ->
        {:ok, current} = owned(repo, user.id, id)

        if current.metadata["phoenix_import_uploaded"] == true do
          :ok
        else
          put_reserved!(config, path, blob)

          metadata =
            current.metadata |> Map.put("phoenix_import_uploaded", true) |> Jason.encode!()

          try do
            repo.query!(
              "UPDATE public.active_storage_blobs SET metadata=$2 WHERE id=$1",
              [id, metadata],
              log: false
            )

            :ok
          rescue
            error ->
              Storage.delete(config, blob.key)
              reraise error, __STACKTRACE__
          end
        end
    end
  end

  defp put_reserved!(%{service: "local", root: root}, path, blob) do
    dest = Storage.disk_path(root, blob.key)
    File.mkdir_p!(Path.dirname(dest))
    File.rename!(path, dest)
  end

  defp put_reserved!(%{service: "s3"} = config, path, blob) do
    headers = %{
      "content-type" => blob.content_type,
      "content-disposition" => Storage.content_disposition("attachment", blob.filename)
    }

    Dawarich.Storage.S3.put!(config, path, blob.key, headers, blob.checksum, blob.byte_size)
  end

  defp owned(repo, user_id, id) do
    case repo.query!("SELECT #{@select} FROM public.active_storage_blobs WHERE id=$1", [id],
           log: false
         ).rows do
      [row] ->
        blob = Map.new(Enum.zip(@columns, row))

        metadata =
          case blob.metadata do
            value when is_map(value) -> value
            value when is_binary(value) -> Jason.decode!(value)
            _ -> %{}
          end

        if metadata["phoenix_import_owner"] == user_id,
          do: {:ok, %{blob | metadata: metadata}},
          else: {:error, :forbidden}

      _ ->
        {:error, :not_found}
    end
  end

  defp sign(purpose, user_id, id),
    do: Phoenix.Token.sign(Endpoint, "imports-" <> purpose, {user_id, id})

  defp verify(purpose, user_id, token) when is_binary(token) do
    case Phoenix.Token.verify(Endpoint, "imports-" <> purpose, token,
           max_age: if(purpose == "write", do: 300, else: :infinity)
         ) do
      {:ok, {^user_id, id}} when is_integer(id) and id > 0 -> {:ok, id}
      {:ok, _} -> {:error, :forbidden}
      _ -> {:error, :invalid_token}
    end
  end

  defp verify(_, _, _), do: {:error, :invalid_token}

  defp admission(user, attrs) do
    cond do
      not Dawarich.Entitlements.future?(user.active_until, DateTime.utc_now()) ->
        {:error, :inactive}

      user.status == 2 and user.subscription_source in [nil, 0] and is_integer(attrs["byte_size"]) and
          attrs["byte_size"] > 11 * 1024 * 1024 ->
        {:error, :file_too_large}

      true ->
        :ok
    end
  end

  defp valid(%{
         "filename" => name,
         "byte_size" => size,
         "checksum" => checksum,
         "content_type" => type
       })
       when is_binary(name) and is_integer(size) and size >= 0 and is_binary(checksum) and
              is_binary(type) do
    with true <-
           name != "" and Path.basename(name) == name and
             not String.contains?(name, ["\\", "\0", "\r", "\n"]),
         true <- String.downcase(Path.extname(name)) in @extensions,
         {:ok, raw} <- Base.decode64(checksum),
         true <- byte_size(raw) == 16,
         true <- byte_size(type) < 256 and not String.contains?(type, ["\r", "\n"]) do
      :ok
    else
      _ -> {:error, :invalid_blob}
    end
  end

  defp valid(_), do: {:error, :invalid_blob}
end
