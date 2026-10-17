defmodule Dawarich.Tracks.ChunkWorker do
  @moduledoc false
  use Oban.Worker, queue: :tracks, max_attempts: 3

  require Logger

  alias Dawarich.Tracks.{Builder, Generation, Points, Settings}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts, conf: conf}),
    do: run(Dawarich.Jobs.repo(), conf.name, args, attempt: attempt, max_attempts: max_attempts)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  def run(repo, _oban, %{"generation_id" => id, "chunk_id" => chunk_id}, opts \\ []) do
    with %{} = chunk <- Generation.chunk(repo, id, chunk_id),
         %{} = user <- Settings.find(repo, chunk.user_id) do
      created = process(repo, user, chunk, Keyword.get(opts, :hook, fn _stage -> :ok end))
      Generation.chunk_done!(repo, id, chunk_id, created)
    end

    :ok
  rescue
    error ->
      if Keyword.get(opts, :attempt, 1) >= Keyword.get(opts, :max_attempts, 3),
        do: Generation.fail!(repo, id, Exception.message(error))

      reraise error, __STACKTRACE__
  end

  defp process(repo, user, chunk, hook) do
    points =
      Points.load_chunk(repo, user.id, chunk.buffer_start_ts, chunk.buffer_end_ts,
        untracked_only: chunk.untracked_only,
        import_id: chunk.import_id
      )

    hook.(:loaded)

    points
    |> Points.segments(Settings.minutes_between_routes(user))
    |> Enum.filter(&claimable?(&1, chunk))
    |> Enum.map(&create(repo, user, &1, chunk.import_id != nil))
    |> Enum.sum()
  end

  defp claimable?(segment, chunk),
    do:
      hd(segment).timestamp <= chunk.end_ts and List.last(segment).timestamp >= chunk.start_ts and
        Enum.any?(segment, &is_nil(&1.track_id))

  defp create(repo, user, segment, claim_all) do
    case Builder.create_from_orphans!(repo, user, segment, claim_all: claim_all) do
      {:ok, tracks} -> length(tracks)
      {:error, _reason} -> 0
    end
  rescue
    error ->
      Logger.warning(
        "event=tracks.chunk_segment_failed user_id=#{user.id} error=#{Exception.message(error)}"
      )

      0
  end
end
