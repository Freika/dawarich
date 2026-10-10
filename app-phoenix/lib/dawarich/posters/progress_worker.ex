defmodule Dawarich.Posters.ProgressWorker do
  @moduledoc false
  use Oban.Worker, queue: :posters, max_attempts: 26
  alias Dawarich.Jobs.Processed
  alias DawarichWeb.MapGalleryCards

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, args) do
    case repo.transaction(fn ->
           if Processed.claim!(repo, args["event_id"], "posters.progress") do
             publish(repo, args)
           end

           :ok
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp publish(repo, args) do
    id = args["poster_id"]
    user = args["user_id"]

    case repo.query!(
           "SELECT name,status,settings FROM posters WHERE id=$1 AND user_id=$2 FOR SHARE",
           [id, user],
           log: false
         ).rows do
      [[name, status, settings]] ->
        files =
          repo.query!(
            "SELECT a.name,b.id,b.filename FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.record_type='Poster' AND a.record_id=$1 AND a.name IN ('image','print_pdf')",
            [id],
            log: false
          ).rows
          |> Map.new(fn [name, blob_id, filename] ->
            {name, %{id: blob_id, filename: filename}}
          end)

        poster = %{id: id, name: name, status: status, settings: settings, files: files}

        html =
          MapGalleryCards.poster_card(%{__changed__: nil, poster: poster, locale: args["locale"]})
          |> Phoenix.HTML.Safe.to_iodata()
          |> IO.iodata_to_binary()

        case Dawarich.Cable.turbo([{:user, user}, "posters"], "replace", "poster_#{id}", html,
               repo: repo
             ) do
          :ok -> :ok
          {:error, reason} -> repo.rollback(reason)
        end

      [] ->
        :ok
    end
  end
end
