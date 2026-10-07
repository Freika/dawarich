defmodule Dawarich.Exports.PurgeWorker do
  @moduledoc false
  use Oban.Worker, queue: :exports, max_attempts: 26
  alias Dawarich.Storage
  alias Dawarich.Storage.Blobs

  def enqueue!(repo, blob_ids) do
    ids = collect(repo, blob_ids, MapSet.new()) |> MapSet.to_list()
    blobs = locked(repo, ids)
    eligible = eligible(repo, Enum.map(blobs, &hd/1))

    objects =
      for [id, key, service, _] <- blobs,
          MapSet.member?(eligible, id),
          do: %{"blob_id" => id, "key" => key, "service_name" => service}

    if objects != [] do
      repo.query!(
        "UPDATE active_storage_blobs SET metadata=(coalesce(nullif(metadata,''),'{}')::jsonb || '{\"phoenix_purge_pending\":true}'::jsonb)::text WHERE id=ANY($1)",
        [MapSet.to_list(eligible)],
        log: false
      )

      repo.insert!(new(%{"objects" => objects}), prefix: "oban")
    end

    :ok
  end

  defp collect(_repo, [], seen), do: seen

  defp collect(repo, [id | rest], seen) do
    if MapSet.member?(seen, id) do
      collect(repo, rest, seen)
    else
      children =
        repo.query!(
          "SELECT a.blob_id FROM active_storage_variant_records v JOIN active_storage_attachments a ON a.record_type='ActiveStorage::VariantRecord' AND a.record_id=v.id WHERE v.blob_id=$1",
          [id],
          log: false
        ).rows
        |> List.flatten()

      collect(repo, children ++ rest, MapSet.put(seen, id))
    end
  end

  defp locked(repo, ids),
    do:
      repo.query!(
        "SELECT id,key,service_name,metadata FROM active_storage_blobs WHERE id=ANY($1) ORDER BY id FOR UPDATE",
        [ids],
        log: false
      ).rows

  defp eligible(repo, ids) do
    candidates = MapSet.new(ids)

    references =
      repo.query!(
        "SELECT a.blob_id,v.blob_id FROM active_storage_attachments a LEFT JOIN active_storage_variant_records v ON a.record_type='ActiveStorage::VariantRecord' AND a.record_id=v.id WHERE a.blob_id=ANY($1)",
        [ids],
        log: false
      ).rows

    protect(candidates, references)
  end

  defp protect(candidates, references) do
    remaining =
      Enum.reduce(references, candidates, fn [child, parent], set ->
        if MapSet.member?(candidates, parent), do: set, else: MapSet.delete(set, child)
      end)

    if remaining == candidates, do: remaining, else: protect(remaining, references)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(args)

  def run(%{"objects" => objects}, opts \\ []) do
    services = Keyword.get_lazy(opts, :services, fn -> Storage.services!(System.get_env()) end)
    repo = Keyword.get_lazy(opts, :repo, &Dawarich.Jobs.repo/0)
    {bound, legacy} = Enum.split_with(objects, &is_integer(&1["blob_id"]))

    with :ok <- delete_objects(services, legacy) do
      purge(repo, services, bound)
    end
  end

  defp purge(repo, services, objects) do
    repo.transaction(fn ->
      targets = Map.new(objects, &{&1["blob_id"], &1})
      blobs = locked(repo, Map.keys(targets))

      current =
        for [id, key, service, metadata] <- blobs,
            targets[id]["key"] == key and targets[id]["service_name"] == service and
              Blobs.purging?(metadata),
            do: id

      eligible = eligible(repo, current)
      protected = current -- MapSet.to_list(eligible)

      repo.query!(
        "UPDATE active_storage_blobs SET metadata=(metadata::jsonb - 'phoenix_purge_pending')::text WHERE id=ANY($1)",
        [protected],
        log: false
      )

      objects = Enum.filter(objects, &MapSet.member?(eligible, &1["blob_id"]))

      case delete_objects(services, objects) do
        :ok ->
          ids = MapSet.to_list(eligible)

          repo.query!(
            "DELETE FROM active_storage_attachments WHERE record_type='ActiveStorage::VariantRecord' AND record_id IN (SELECT id FROM active_storage_variant_records WHERE blob_id=ANY($1))",
            [ids],
            log: false
          )

          repo.query!("DELETE FROM active_storage_variant_records WHERE blob_id=ANY($1)", [ids],
            log: false
          )

          repo.query!("DELETE FROM active_storage_blobs WHERE id=ANY($1)", [ids], log: false)

        {:error, reason} ->
          repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_objects(services, objects) do
    Enum.reduce_while(objects, :ok, fn object, :ok ->
      case Storage.delete(Storage.service!(services, object["service_name"]), object["key"]) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:storage_delete, reason}}}
      end
    end)
  end
end
