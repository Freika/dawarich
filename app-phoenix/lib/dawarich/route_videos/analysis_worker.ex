defmodule Dawarich.RouteVideos.AnalysisWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :route_videos,
    max_attempts: 26,
    unique: [keys: [:blob_id], states: :incomplete, period: :infinity]

  alias Dawarich.{Jobs, Storage}
  alias Dawarich.Jobs.Processed
  alias Dawarich.RouteVideos.VideoMetadata

  def enqueue!(repo, user, video, blob) do
    args = %{
      "user_id" => user,
      "video_id" => video,
      "blob_id" => blob,
      "event_id" => Ecto.UUID.generate()
    }

    {_key, _service, _type, metadata} = blob(repo, args)
    metadata = Jason.decode!(metadata || "{}")

    unless metadata["identified"] == true and metadata["analyzed"] == true do
      repo.insert!(new(args), prefix: "oban")
    end

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Jobs.repo(), args)

  def run(repo, args, opts \\ []) do
    if Processed.done?(repo, args["event_id"]) do
      :ok
    else
      case blob(repo, args) do
        nil ->
          :ok

        {key, service, type, metadata} ->
          metadata = Jason.decode!(metadata || "{}")

          if metadata["identified"] == true and metadata["analyzed"] == true do
            :ok
          else
            services =
              Keyword.get_lazy(opts, :services, fn -> Storage.services!(System.get_env()) end)

            storage = Storage.service!(services, service)
            dir = Storage.tmp_dir!(storage, "route-video-analysis-" <> args["event_id"])
            path = Path.join(dir, "video")

            try do
              Storage.download!(storage, key, path)
              type = Dawarich.Storage.ImageVariant.identify(path, type)

              result =
                if String.starts_with?(type, "video/"),
                  do: VideoMetadata.read(path, opts),
                  else: %{}

              metadata =
                Map.merge(metadata, result)
                |> Map.merge(%{"identified" => true, "analyzed" => true})

              Processed.once(repo, args["event_id"], "route_videos.analysis", fn ->
                if blob(repo, args, "FOR UPDATE OF b") != nil do
                  repo.query!(
                    "UPDATE active_storage_blobs SET metadata=$2,content_type=$3 WHERE id=$1",
                    [args["blob_id"], Jason.encode!(metadata), type],
                    log: false
                  )
                end

                :ok
              end)
            after
              File.rm_rf!(dir)
            end
          end
      end
    end
  end

  defp blob(repo, args, lock \\ "") do
    case repo.query!(
           "SELECT b.key,b.service_name,b.content_type,b.metadata FROM active_storage_blobs b JOIN active_storage_attachments a ON a.blob_id=b.id JOIN route_videos v ON v.id=a.record_id WHERE b.id=$1 AND v.id=$2 AND v.user_id=$3 AND a.record_type='RouteVideo' AND a.name='file' #{lock}",
           [args["blob_id"], args["video_id"], args["user_id"]],
           log: false
         ).rows do
      [[key, service, type, metadata]] -> {key, service, type, metadata}
      [] -> nil
    end
  end
end
