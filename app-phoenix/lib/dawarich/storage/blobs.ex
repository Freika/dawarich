defmodule Dawarich.Storage.Blobs do
  @moduledoc false

  alias Dawarich.{RailsMessages, RailsTime, Repo, Storage}

  @protected ~w(analyzed identified composed phoenix_purge_pending)

  @insert """
  INSERT INTO active_storage_blobs (key, filename, content_type, metadata, service_name, byte_size, checksum, created_at)
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id
  """

  def find(id), do: select(id)

  def attach!(repo, type, record, blob, now) do
    [[id]] =
      repo.query!(
        @insert,
        [
          blob.key,
          blob.filename,
          blob.content_type,
          blob.metadata,
          Map.get(blob, :stored_service, blob.service_name),
          blob.byte_size,
          blob.checksum,
          now
        ],
        log: false
      ).rows

    repo.query!(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file',$1,$2,$3,$4)",
      [type, record, id, now],
      log: false
    )

    id
  end

  def create_before_direct_upload(config, attrs, %NaiveDateTime{} = now, opts \\ []) do
    key = Keyword.get_lazy(opts, :key, fn -> &Storage.generate_key/0 end).()
    zone = Keyword.get_lazy(opts, :zone, fn -> System.get_env("TIME_ZONE", "Europe/Berlin") end)
    metadata = RailsMessages.json(Map.drop(attrs["metadata"] || %{}, @protected))
    service = Map.get(config, :stored_service, config.service)

    row = [
      key,
      attrs["filename"],
      attrs["content_type"],
      metadata,
      service,
      attrs["byte_size"],
      attrs["checksum"],
      now
    ]

    RailsTime.with_zone(zone, fn ->
      Repo.transaction(fn ->
        %{rows: [[id]]} = Repo.query!(@insert, row)

        if Keyword.has_key?(opts, :user_id),
          do: Dawarich.Storage.UploadReceipts.bind!(Repo, id, opts[:user_id])

        select(id)
      end)
    end)
  end

  defp select(id) do
    sql =
      "SELECT *, " <>
        RailsTime.sql("created_at", 3) <>
        " AS created_at_json FROM active_storage_blobs WHERE id = $1"

    case Repo.query!(sql, [id]) do
      %{columns: columns, rows: [row]} ->
        value = blob(Enum.zip(columns, row))
        unless Dawarich.Storage.NativePurge.pending?(value.metadata), do: value

      _ ->
        nil
    end
  end

  defp blob(pairs) do
    attrs = Map.new(pairs)

    %{
      id: attrs["id"],
      key: attrs["key"],
      filename: attrs["filename"],
      content_type: attrs["content_type"],
      metadata: attrs["metadata"],
      service_name: attrs["service_name"],
      byte_size: attrs["byte_size"],
      checksum: attrs["checksum"],
      created_at_json: attrs["created_at_json"],
      pairs: Enum.reject(pairs, &(elem(&1, 0) == "created_at_json"))
    }
  end
end
