defmodule Dawarich.Trips.AnalyzeAttachmentWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :trips,
    max_attempts: 26,
    unique: [keys: [:blob_id], states: :incomplete, period: :infinity]

  alias Dawarich.Storage
  alias Dawarich.Storage.{ImageVariant, NativePurge}

  def enqueue!(repo, id) do
    [[metadata]] =
      repo.query!("SELECT metadata FROM active_storage_blobs WHERE id=$1", [id], log: false).rows

    unless Jason.decode!(metadata || "{}")["analyzed"],
      do: repo.insert!(new(%{"blob_id" => id}), prefix: "oban")

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"blob_id" => id}}) do
    repo = Dawarich.Jobs.repo()

    case repo.transaction(fn -> analyze(repo, id) end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp analyze(repo, id) do
    case repo.query!(
           "SELECT key,filename,service_name,content_type,checksum,metadata FROM active_storage_blobs WHERE id=$1 FOR UPDATE",
           [id],
           log: false
         ).rows do
      [[key, _filename, service, type, checksum, metadata]] ->
        if NativePurge.pending?(metadata) do
          :ok
        else
          config = Storage.service!(Storage.services!(System.get_env()), service)
          dir = Storage.tmp_dir!(config, "trip-analysis-" <> Ecto.UUID.generate())
          file = Path.join(dir, "input")

          try do
            Storage.download!(config, key, file)
            {digest, _} = Storage.digest_file!(file)

            unless Jason.decode!(metadata || "{}")["composed"] || digest == checksum,
              do: raise(ArgumentError, "ActiveStorage integrity error")

            type =
              if Jason.decode!(metadata || "{}")["identified"],
                do: type,
                else: ImageVariant.identify(file, type)

            analyzed = metadata(file, type || "")

            value =
              Jason.decode!(metadata || "{}")
              |> Map.merge(analyzed)
              |> Map.merge(%{"identified" => true, "analyzed" => true})

            repo.query!(
              "UPDATE active_storage_blobs SET metadata=$2,content_type=$3 WHERE id=$1",
              [id, Jason.encode!(value), type],
              log: false
            )

            :ok
          after
            File.rm_rf!(dir)
          end
        end

      [] ->
        :ok
    end
  end

  defp metadata(file, type) do
    if String.starts_with?(type, ["image/", "video/", "audio/"]) do
      probe = probe(file)
      streams = probe["streams"] || []
      video = Enum.find(streams, &(&1["codec_type"] == "video")) || %{}
      audio = Enum.find(streams, &(&1["codec_type"] == "audio")) || %{}

      cond do
        String.starts_with?(type, "image/") -> Map.take(video, ~w(width height))
        String.starts_with?(type, "audio/") -> audio_metadata(audio)
        true -> video_metadata(video, audio, probe["format"] || %{})
      end
    else
      %{}
    end
  end

  defp probe(file) do
    if tool = System.find_executable("ffprobe") do
      case System.cmd(
             tool,
             ["-print_format", "json", "-show_streams", "-show_format", "-v", "quiet", file],
             stderr_to_stdout: true
           ) do
        {json, 0} -> Jason.decode!(json)
        _ -> %{}
      end
    else
      %{}
    end
  end

  defp audio_metadata(audio) do
    %{
      "duration" => number(audio["duration"]),
      "bit_rate" => integer(audio["bit_rate"]),
      "sample_rate" => integer(audio["sample_rate"]),
      "tags" => audio["tags"]
    }
    |> compact()
  end

  defp video_metadata(video, audio, container) do
    ratio =
      case String.split(video["display_aspect_ratio"] || "", ":") do
        [first, last] -> if integer(first) not in [nil, 0], do: [integer(first), integer(last)]
        _ -> nil
      end

    matrix =
      Enum.find(video["side_data_list"] || [], &(&1["side_data_type"] == "Display Matrix")) || %{}

    angle = integer((video["tags"] || %{})["rotate"] || matrix["rotation"])
    width = number(video["width"])

    height =
      if width && ratio, do: width * List.last(ratio) / hd(ratio), else: number(video["height"])

    {width, height} = if angle in [90, -90, 270, -270], do: {height, width}, else: {width, height}

    %{
      "width" => width,
      "height" => height,
      "duration" => number(video["duration"] || container["duration"]),
      "angle" => angle,
      "display_aspect_ratio" => ratio,
      "audio" => map_size(audio) > 0,
      "video" => map_size(video) > 0
    }
    |> compact()
  end

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
  defp number(nil), do: nil
  defp number(value) when is_number(value), do: value * 1.0

  defp number(value),
    do: String.to_float(if String.contains?(value, "."), do: value, else: value <> ".0")

  defp integer(nil), do: nil
  defp integer(value) when is_integer(value), do: value
  defp integer(value) when is_float(value), do: trunc(value)
  defp integer(value), do: String.to_integer(value)
end
