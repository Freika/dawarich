defmodule Dawarich.Tracks.MapMatching.Worker do
  use Oban.Worker,
    queue: :map_matching,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:track_id, :digest],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Dawarich.Experimental
  alias Dawarich.MapMatching.{Fingerprint, Input, Processor, QualityPolicy}
  alias Dawarich.MapMatching.Atlas.Client.Error
  alias Dawarich.Tracks.{Effects, Store}
  alias Dawarich.Tracks.MapMatching.State

  @codes ~w(invalid_input invalid_request provider_invalid invalid_url connection_failed capacity rate_limited unavailable timeout request_timeout response_too_large http_error malformed_response processing_failed)

  @impl Oban.Worker
  def perform(%Oban.Job{conf: conf} = job), do: run(conf.repo, job)

  def run(repo, %Oban.Job{args: %{"track_id" => id, "digest" => digest}} = job) do
    if Experimental.map_matching?(repo) do
      {:ok, input} = repo.transaction(fn -> snapshot(repo, id, digest) end)

      if input do
        case Processor.call(input) do
          {:ok, result} -> publish(repo, id, digest, result)
          {:error, error} -> failed(repo, id, digest, sanitize(error), job)
        end
      else
        :ok
      end
    else
      :ok
    end
  rescue
    _ -> failed(repo, id, digest, %Error{code: "processing_failed", transient?: true}, job)
  end

  defp snapshot(repo, id, digest) do
    if Store.get(repo, id, true) && current?(State.read(repo, id), digest) do
      input = Input.load(repo, id)
      if Fingerprint.call(input) == digest, do: input
    end
  end

  defp current?(%{status: :pending, digest: digest}, digest), do: true
  defp current?(_, _), do: false

  defp failed(repo, id, digest, error, job) do
    attempt = job.attempt + Map.get(job.meta || %{}, "snoozed", 0)

    cond do
      attempt >= 5 or not error.transient? ->
        publish(repo, id, digest, %{
          status: :failed,
          path: nil,
          data: %{
            schema_version: 1,
            policy_version: QualityPolicy.version(),
            provider: %{name: "atlas"},
            segments: [],
            error: %{
              code: error.code,
              status: error.status,
              attempt: attempt,
              message: error.code
            }
          }
        })

      error.status == 429 ->
        {:snooze, error.retry_after || backoff(job)}

      true ->
        {:error, error}
    end
  end

  defp sanitize(error) do
    %Error{
      code: if(Map.get(error, :code) in @codes, do: error.code, else: "provider_error"),
      status: if(is_integer(Map.get(error, :status)), do: error.status),
      transient?: Map.get(error, :transient?, false),
      retry_after:
        if(is_integer(Map.get(error, :retry_after)) and error.retry_after > 0,
          do: error.retry_after
        )
    }
  end

  defp publish(repo, id, digest, result) do
    {:ok, _} =
      repo.transaction(fn ->
        track = Store.get(repo, id, true)

        if track && current?(State.read(repo, id), digest) &&
             Experimental.map_matching?(repo) &&
             Fingerprint.call(Input.load(repo, id)) == digest do
          State.write!(repo, id, %{
            status: result.status,
            matched_path: result.path,
            data: result.data,
            matched_at: DateTime.utc_now()
          })

          Effects.write!(repo, track.user_id, %{
            updated: [id],
            stamps: [track.start_at, track.end_at]
          })
        end
      end)

    :ok
  end
end
