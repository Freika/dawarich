defmodule Dawarich.Storage.NativePurge do
  @moduledoc false

  def unmarked_ids(repo, ids) do
    repo.query!(
      "SELECT id,metadata FROM active_storage_blobs WHERE id=ANY($1) ORDER BY id FOR UPDATE",
      [ids],
      log: false
    ).rows
    |> Enum.reject(fn [_id, metadata] -> pending?(metadata) end)
    |> Enum.map(&hd/1)
  end

  def collect(repo, ids) do
    blobs =
      repo.query!(
        """
        WITH RECURSIVE purge(id) AS (
          SELECT id FROM active_storage_blobs WHERE id=ANY($1)
          UNION
          SELECT a.blob_id FROM purge p
          JOIN active_storage_variant_records v ON v.blob_id=p.id
          JOIN active_storage_attachments a ON a.record_id=v.id
            AND a.record_type='ActiveStorage::VariantRecord'
        )
        SELECT b.id,b.key,b.service_name FROM active_storage_blobs b
        JOIN purge p ON p.id=b.id ORDER BY b.id FOR UPDATE OF b
        """,
        [ids],
        log: false
      ).rows

    references =
      repo.query!(
        """
        SELECT a.blob_id,v.blob_id FROM active_storage_attachments a
        LEFT JOIN active_storage_variant_records v ON v.id=a.record_id
          AND a.record_type='ActiveStorage::VariantRecord'
        WHERE a.blob_id=ANY($1)
        """,
        [Enum.map(blobs, &hd/1)],
        log: false
      ).rows

    eligible = eligible_ids(MapSet.new(blobs, &hd/1), references)

    for [id, key, service] <- blobs,
        MapSet.member?(eligible, id),
        do: %{"blob_id" => id, "key" => key, "service_name" => service}
  end

  def mark!(repo, objects) do
    for object <- objects do
      [[metadata]] =
        repo.query!("SELECT metadata FROM active_storage_blobs WHERE id=$1", [object["blob_id"]],
          log: false
        ).rows

      metadata =
        case Jason.decode(metadata || "{}") do
          {:ok, %{} = value} -> value
          _ -> %{}
        end

      repo.query!(
        "UPDATE active_storage_blobs SET metadata=$2 WHERE id=$1",
        [object["blob_id"], Jason.encode!(Map.put(metadata, "phoenix_purge_pending", true))],
        log: false
      )
    end
  end

  def pending?(metadata) when is_binary(metadata) do
    case Jason.decode(metadata) do
      {:ok, %{"phoenix_purge_pending" => true}} -> true
      _ -> false
    end
  end

  def pending?(_metadata), do: false

  def remove!(repo, objects) do
    ids = Enum.map(objects, & &1["blob_id"])

    repo.query!(
      "DELETE FROM active_storage_attachments WHERE record_type='ActiveStorage::VariantRecord' AND record_id IN (SELECT id FROM active_storage_variant_records WHERE blob_id=ANY($1))",
      [ids],
      log: false
    )

    repo.query!("DELETE FROM active_storage_variant_records WHERE blob_id=ANY($1)", [ids],
      log: false
    )

    repo.query!("DELETE FROM active_storage_blobs WHERE id=ANY($1)", [ids], log: false)
  end

  defp eligible_ids(ids, references) do
    remaining =
      Enum.reduce(references, ids, fn [blob, parent], eligible ->
        if MapSet.member?(ids, parent), do: eligible, else: MapSet.delete(eligible, blob)
      end)

    if remaining == ids, do: ids, else: eligible_ids(remaining, references)
  end
end
