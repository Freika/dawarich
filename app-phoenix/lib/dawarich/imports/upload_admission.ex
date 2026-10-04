defmodule Dawarich.Imports.UploadAdmission do
  @moduledoc false
  alias Dawarich.Imports.{
    Uploads,
    Tempfiles,
    ArchiveDispatch,
    ArchivePaths,
    SourceDetector,
    UiRecords
  }

  alias Dawarich.Storage

  def prepare(repo, files, context) do
    Enum.reduce_while(files, {:ok, []}, fn raw, {:ok, acc} ->
      descriptor = descriptor(raw)

      with {:ok, blob} <- Uploads.fetch(repo, descriptor["signed_id"]),
           name = original(descriptor, blob.filename) || blob.filename,
           {:ok, source} <- classify(blob, name, context) do
        metadata = metadata(descriptor, blob.metadata, name, blob.filename)
        {:cont, {:ok, acc ++ [%{blob: blob, name: name, source: source, metadata: metadata}]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp metadata(descriptor, metadata, name, filename) do
    metadata =
      if Map.has_key?(descriptor, "client_wrapped"),
        do: Map.put(metadata, "dawarich_client_wrapped", descriptor["client_wrapped"] == true),
        else: metadata

    if name != filename,
      do: Map.put(metadata, "dawarich_original_filename", name),
      else: metadata
  end

  defp descriptor(value) when is_map(value), do: value

  defp descriptor(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, %{} = descriptor} -> descriptor
      _ -> %{"signed_id" => value}
    end
  end

  defp descriptor(_), do: %{}

  defp original(%{"client_wrapped" => true, "original_filename" => name}, filename)
       when is_binary(name) do
    if name != "" and Path.basename(name) == name and filename == name <> ".zip", do: name
  end

  defp original(_, _), do: nil

  defp classify(%{byte_size: 0}, _, _), do: {:error, :rails_format}

  defp classify(blob, name, context) do
    Tempfiles.with_files(fn adopt ->
      services =
        Map.get_lazy(context, :services, fn ->
          config = Map.fetch!(context, :storage)
          %{Map.get(config, :stored_service, config.service) => config}
        end)

      {:ok, config} = Storage.ImportServices.resolve(services, blob)
      path = Storage.Reader.download!(config, blob, on_verified: adopt)
      opts = [on_verified: adopt]

      case ArchiveDispatch.inspect(path, opts) do
        :multi_entry -> {:ok, nil}
        :user_data_archive -> {:ok, 8}
        {:single_entry, entry} -> detect(ArchivePaths.extract(path, entry, opts), entry.name)
        :not_a_zip -> detect(path, name)
        {:legacy, _} -> {:error, :rails_format}
      end
    end)
  rescue
    _error -> {:error, :rails_format}
  end

  defp detect(path, name) do
    source = SourceDetector.detect(path, name)
    index = Enum.find_index(UiRecords.sources(), &(&1 == Atom.to_string(source || :unknown)))
    if is_integer(index) and index != 8, do: {:ok, index}, else: {:error, :rails_format}
  end

  def user!(repo, id) do
    case repo.query!(
           "SELECT id,status,subscription_source,active_until,points_count,settings FROM public.users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
           [id],
           log: false
         ).rows do
      [[id, status, subscription, active, count, settings]] ->
        %{
          id: id,
          status: status,
          subscription_source: subscription,
          active_until: active,
          points_count: count || 0,
          settings: settings || %{}
        }

      _ ->
        repo.rollback(:forbidden)
    end
  end

  def admission!(repo, user, added, context) do
    unless Dawarich.Entitlements.future?(user.active_until, DateTime.utc_now()),
      do: repo.rollback(:inactive)

    if not context.self_hosted? and user.points_count >= 10_000_000,
      do: repo.rollback(:points_limit)

    if trial?(user) do
      [[count]] =
        repo.query!(
          "SELECT count(*) FROM public.imports WHERE user_id=$1 AND demo=false",
          [user.id],
          log: false
        ).rows

      if count + added > 5, do: repo.rollback(:import_limit)
    end
  end

  defp trial?(user), do: user.status == 2 and user.subscription_source in [nil, 0]
end
