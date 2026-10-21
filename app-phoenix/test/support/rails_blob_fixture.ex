defmodule Dawarich.RailsBlobFixture do
  @moduledoc false

  def create!(repo, root, name, bytes, opts \\ []) do
    key = Dawarich.Storage.generate_key()
    path = Dawarich.Storage.disk_path(root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)

    [[id]] =
      repo.query!(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES($1,$2,$3,$4,'local',$5,$6,now()) RETURNING id",
        [
          key,
          name,
          Keyword.get(opts, :content_type, "application/octet-stream"),
          Jason.encode!(Keyword.get(opts, :metadata, %{})),
          byte_size(bytes),
          Base.encode64(:crypto.hash(:md5, bytes))
        ],
        log: false
      ).rows

    if user_id = opts[:user_id], do: Dawarich.Storage.UploadReceipts.bind!(repo, id, user_id)

    %{id: id, signed_id: Dawarich.RailsMessages.blob_id(id)}
  end
end
