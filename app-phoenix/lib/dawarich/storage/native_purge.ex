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

  def collect(repo, ids), do: Enum.flat_map(ids, &collect(repo, &1, [], [])) |> Enum.uniq()

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

  defp collect(repo, id, ignored, ancestors) do
    if id in ancestors do
      []
    else
      case repo.query!(
             "SELECT key,service_name FROM active_storage_blobs WHERE id=$1 FOR UPDATE",
             [id],
             log: false
           ).rows do
        [[key, service]] ->
          [[referenced]] =
            repo.query!(
              "SELECT EXISTS(SELECT 1 FROM active_storage_attachments WHERE blob_id=$1 AND NOT(id=ANY($2)))",
              [id, ignored],
              log: false
            ).rows

          if referenced do
            []
          else
            children =
              repo.query!(
                "SELECT a.id,a.blob_id FROM active_storage_attachments a JOIN active_storage_variant_records v ON v.id=a.record_id WHERE a.record_type='ActiveStorage::VariantRecord' AND v.blob_id=$1 ORDER BY a.blob_id,a.id",
                [id],
                log: false
              ).rows

            child_objects =
              children
              |> Enum.group_by(&List.last/1, &hd/1)
              |> Enum.sort()
              |> Enum.flat_map(fn {child, attachments} ->
                collect(repo, child, attachments, [id | ancestors])
              end)

            [%{"blob_id" => id, "key" => key, "service_name" => service} | child_objects]
          end

        [] ->
          []
      end
    end
  end
end
