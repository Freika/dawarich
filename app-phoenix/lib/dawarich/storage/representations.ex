defmodule Dawarich.Storage.Representations do
  @moduledoc false
  alias Dawarich.{Repo, Storage}
  alias Dawarich.Storage.{Blobs, ImageVariant, Variation}

  @images ~w(image/png image/gif image/jpeg image/tiff image/bmp image/vnd.adobe.photoshop image/vnd.microsoft.icon image/webp image/avif image/heic image/heif)

  def representable?(blob), do: blob.content_type in @images or previewable?(blob)

  def processed(blob, variation, storage, now, opts \\ []) do
    cond do
      blob.content_type in @images -> variant(blob, variation, storage, now, opts)
      previewable?(blob) -> preview(blob, variation, storage, now, opts)
      true -> {:error, :unrepresentable}
    end
  rescue
    _ -> {:error, :processing}
  end

  defp previewable?(blob) do
    cond do
      blob.content_type == "application/pdf" ->
        System.find_executable("pdftoppm") != nil

      String.starts_with?(blob.content_type || "", "video/") ->
        System.find_executable("ffmpeg") != nil

      true ->
        false
    end
  end

  defp variant(blob, variation, storage, now, opts) do
    variation = Variation.default(variation, default_format(blob))
    format = variation.transformations["format"]

    if ImageVariant.format_type(format) == :error do
      {:error, :invalid_format}
    else
      digest = Variation.digest(variation)

      case existing(blob.id, digest) do
        nil ->
          representation(process(blob, variation, digest, storage, now, opts), MIME.type(format))

        image ->
          representation({:ok, image}, MIME.type(format))
      end
    end
  end

  defp representation({:ok, image}, type),
    do: {:ok, Map.put(image, :representation_content_type, type)}

  defp representation(error, _type), do: error

  defp process(blob, variation, digest, storage, now, opts) do
    service = Storage.service!(storage, blob.service_name)
    dir = Storage.tmp_dir!(service, "variant-" <> Storage.generate_key())

    try do
      path = ImageVariant.transform!(service, blob, variation, dir)
      format = variation.transformations["format"]
      filename = Path.rootname(blob.filename) <> "." <> String.downcase(format)
      type = ImageVariant.identify(path, MIME.type(String.downcase(format)))
      {checksum, size} = Storage.digest_file!(path)
      key = Keyword.get_lazy(opts, :key, fn -> &Storage.generate_key/0 end).()

      result =
        Repo.transaction(fn ->
          case Repo.query!(
                 "INSERT INTO active_storage_variant_records(blob_id,variation_digest) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING id",
                 [blob.id, digest]
               ).rows do
            [[id]] ->
              image = create_image(key, filename, type, blob.service_name, checksum, size, now)
              attach("image", "ActiveStorage::VariantRecord", id, image.id, now)
              if callback = opts[:after_variant_insert], do: callback.(image)
              {:created, image}

            [] ->
              {:existing, existing(blob.id, digest)}
          end
        end)

      case result do
        {:ok, {:created, image}} ->
          put_image!(service, path, image)
          if callback = opts[:after_put], do: callback.(image)
          {:ok, image}

        {:ok, {:existing, image}} ->
          {:ok, image}

        _ ->
          {:error, :processing}
      end
    after
      File.rm_rf(dir)
    end
  end

  defp create_image(key, filename, type, name, checksum, size, now) do
    [[id]] =
      Repo.query!(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id",
        [
          key,
          filename,
          type,
          ~s({"identified":true,"analyzed":true}),
          name,
          size,
          checksum,
          DateTime.to_naive(now)
        ]
      ).rows

    Blobs.find(id)
  end

  defp attach(name, type, id, blob_id, now),
    do:
      Repo.query!(
        "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES($1,$2,$3,$4,$5)",
        [name, type, id, blob_id, DateTime.to_naive(now)]
      )

  defp existing(id, digest) do
    case Repo.query!(
           "SELECT a.blob_id FROM active_storage_variant_records v JOIN active_storage_attachments a ON a.record_type='ActiveStorage::VariantRecord' AND a.record_id=v.id AND a.name='image' WHERE v.blob_id=$1 AND v.variation_digest=$2",
           [id, digest]
         ).rows do
      [[blob_id]] -> Blobs.find(blob_id)
      _ -> nil
    end
  end

  defp preview(blob, variation, storage, now, opts) do
    image =
      case Repo.query!(
             "SELECT blob_id FROM active_storage_attachments WHERE record_type='ActiveStorage::Blob' AND record_id=$1 AND name='preview_image'",
             [blob.id]
           ).rows do
        [[id]] -> Blobs.find(id)
        _ -> create_preview(blob, storage, now, opts)
      end

    if map_size(variation.transformations) == 0,
      do: {:ok, image},
      else: variant(image, variation, storage, now, opts)
  end

  defp create_preview(blob, storage, now, opts) do
    service = Storage.service!(storage, blob.service_name)
    dir = Storage.tmp_dir!(service, "preview-" <> Storage.generate_key())

    try do
      {path, format, type} = ImageVariant.preview!(service, blob, dir)
      {checksum, size} = Storage.digest_file!(path)
      key = Keyword.get_lazy(opts, :key, fn -> &Storage.generate_key/0 end).()

      {:ok, image} =
        Repo.transaction(fn ->
          image =
            create_image(
              key,
              Path.rootname(blob.filename) <> "." <> format,
              type,
              blob.service_name,
              checksum,
              size,
              now
            )

          attach("preview_image", "ActiveStorage::Blob", blob.id, image.id, now)
          image
        end)

      put_image!(service, path, image)
      image
    after
      File.rm_rf(dir)
    end
  end

  defp put_image!(%{service: "local", root: root}, path, image) do
    {:ok, dest} = Storage.safe_disk_path(root, image.key)
    File.mkdir_p!(Path.dirname(dest))
    File.rename!(path, dest)
  end

  defp put_image!(%{service: "s3"} = service, path, image),
    do:
      Dawarich.Storage.S3.put!(
        service,
        path,
        image.key,
        %{"content-type" => image.content_type},
        image.checksum,
        image.byte_size
      )

  defp default_format(blob) do
    extension = blob.filename |> Path.extname() |> String.trim_leading(".") |> String.downcase()

    if blob.content_type in ~w(image/png image/jpeg image/gif image/webp image/avif) do
      if MIME.type(extension) == blob.content_type,
        do: extension,
        else: MIME.extensions(blob.content_type) |> List.first() || "png"
    else
      "png"
    end
  end
end
