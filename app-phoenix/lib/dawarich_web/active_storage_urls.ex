defmodule DawarichWeb.ActiveStorageUrls do
  @moduledoc false

  alias Dawarich.{RailsMessages, Storage}
  alias Dawarich.Storage.S3
  alias DawarichWeb.BlobPath

  @expires_in 300
  @binary ~w(text/html image/svg+xml application/postscript application/x-shockwave-flash text/xml application/xml application/xhtml+xml application/mathml+xml text/cache-manifest)
  @inline ~w(image/webp image/avif image/png image/gif image/jpeg image/tiff image/bmp image/vnd.adobe.photoshop image/vnd.microsoft.icon application/pdf)

  def binary_types, do: @binary
  def inline_types, do: @inline

  def service_url(%{service: service} = config, blob, disposition, base_url, %DateTime{} = now) do
    content_type =
      if blob.content_type in @binary, do: "application/octet-stream", else: blob.content_type

    forced = if blob.content_type in @binary or blob.content_type not in @inline, do: "attachment"
    header = Storage.content_disposition(type(forced || disposition), blob.filename)

    case service do
      "local" ->
        data =
          Jason.OrderedObject.new(
            key: blob.key,
            disposition: header,
            content_type: content_type,
            service_name: blob.service_name
          )

        signed = RailsMessages.sign_storage(data, "blob_key", DateTime.add(now, @expires_in))

        base_url <>
          "/rails/active_storage/disk/" <>
          BlobPath.segment(signed) <>
          "/" <> BlobPath.path(Storage.sanitized_filename(blob.filename))

      "s3" ->
        query =
          [{"response-content-disposition", header}] ++
            if(content_type, do: [{"response-content-type", content_type}], else: [])

        S3.presigned_url!(config, :get, blob.key, query, [], now)
    end
  end

  def direct_upload(%{service: "local"}, blob, base_url, %DateTime{} = now) do
    data =
      Jason.OrderedObject.new(
        key: blob.key,
        content_type: blob.content_type,
        content_length: blob.byte_size,
        checksum: blob.checksum,
        service_name: blob.service_name
      )

    signed = RailsMessages.sign_storage(data, "blob_token", DateTime.add(now, @expires_in))

    {base_url <> "/rails/active_storage/disk/" <> BlobPath.segment(signed),
     Jason.OrderedObject.new([{"Content-Type", blob.content_type}])}
  end

  def direct_upload(%{service: "s3"} = config, blob, _base_url, %DateTime{} = now) do
    signed_headers =
      Enum.reject(
        [
          {"content-length", Integer.to_string(blob.byte_size)},
          {"content-md5", blob.checksum},
          {"content-type", blob.content_type}
        ],
        &is_nil(elem(&1, 1))
      )

    headers =
      Jason.OrderedObject.new([
        {"Content-Type", blob.content_type},
        {"Content-MD5", blob.checksum},
        {"Content-Disposition", Storage.content_disposition("inline", blob.filename)}
      ])

    {S3.presigned_url!(config, :put, blob.key, [], signed_headers, now), headers}
  end

  defp type(value) when value in ["attachment", "inline"], do: value
  defp type(_value), do: "inline"
end
