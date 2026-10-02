defmodule Dawarich.Imports.UiRecords do
  @moduledoc false
  alias Dawarich.Imports.Events

  @sources ~w(google_semantic_history owntracks google_records google_phone_takeout gpx immich_api geojson photoprism_api user_data_archive kml csv tcx fit polarsteps google_photos mobile_photo_library)
  @columns ~w(id user_id name source status processed doubles raw_points raw_data error_message additional_data_extraction_status additional_data_extraction created_at updated_at source_blob_id)a
  @fields "i.id,i.user_id,i.name,i.source,i.status,i.processed,i.doubles,i.raw_points,i.raw_data,i.error_message,i.additional_data_extraction_status,i.additional_data_extraction,i.created_at,i.updated_at,f.blob_id"
  def sources, do: @sources

  def get(repo, user_id, id) do
    with {:ok, id} <- id(id) do
      case repo.query!(
             "SELECT #{@fields} FROM public.imports i JOIN public.users u ON u.id=i.user_id LEFT JOIN LATERAL (SELECT blob_id FROM public.active_storage_attachments WHERE record_type='Import' AND record_id=i.id AND name='file' ORDER BY id LIMIT 1) f ON true WHERE i.id=$1 AND i.user_id=$2 AND u.deleted_at IS NULL",
             [id, user_id],
             log: false
           ).rows do
        [row] -> {:ok, Map.new(Enum.zip(@columns, row))}
        _ -> {:error, :not_found}
      end
    end
  end

  def update(repo, user_id, id, params) do
    with {:ok, id} <- id(id), {:ok, source} <- source(params) do
      repo.transaction(fn ->
        record = lock!(repo, user_id, id)
        name = Map.get(params, "name", record.name)
        unless is_binary(name) and String.trim(name) != "", do: repo.rollback(:invalid_name)

        if repo.query!(
             "SELECT 1 FROM public.imports WHERE user_id=$1 AND name=$2 AND id<>$3 LIMIT 1",
             [user_id, name, id],
             log: false
           ).rows != [],
           do: repo.rollback(:duplicate_name)

        source = if source == :unchanged, do: record.source, else: source
        extraction = record.additional_data_extraction_status

        extraction =
          if extraction in [0, 5],
            do: if(source in [0, 3, 4, 13], do: 0, else: 5),
            else: extraction

        repo.query!(
          "UPDATE public.imports SET name=$3,source=$4,additional_data_extraction_status=$5,updated_at=now() WHERE id=$1 AND user_id=$2",
          [id, user_id, name, source, extraction],
          log: false
        )

        :updated
      end)
      |> notify(user_id)
    end
  end

  def extract(repo, user_id, id, params, context),
    do: Dawarich.Imports.ManualExtraction.enqueue(repo, user_id, id, :extract, params, context)

  def remove_extraction(repo, user_id, id, context),
    do: Dawarich.Imports.ManualExtraction.enqueue(repo, user_id, id, :remove, %{}, context)

  defp lock!(repo, user_id, id) do
    case repo.query!(
           "SELECT i.id FROM public.imports i JOIN public.users u ON u.id=i.user_id WHERE i.id=$1 AND i.user_id=$2 AND u.deleted_at IS NULL FOR UPDATE OF i FOR SHARE OF u",
           [id, user_id],
           log: false
         ).rows do
      [[^id]] ->
        {:ok, record} = get(repo, user_id, id)
        record

      _ ->
        repo.rollback(:not_found)
    end
  end

  defp source(params) do
    case Map.fetch(params, "source") do
      :error ->
        {:ok, :unchanged}

      {:ok, value} when value in [nil, ""] ->
        {:ok, nil}

      {:ok, value} ->
        case Enum.find_index(@sources, &(&1 == value)) do
          nil -> {:error, :invalid_source}
          index -> {:ok, index}
        end
    end
  end

  defp id(value) when is_integer(value) and value > 0 and value <= 9_223_372_036_854_775_807,
    do: {:ok, value}

  defp id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end

  defp id(_), do: {:error, :not_found}

  defp notify({:ok, _} = result, user_id),
    do:
      (
        Events.broadcast(user_id)
        result
      )

  defp notify(result, _), do: result
end
