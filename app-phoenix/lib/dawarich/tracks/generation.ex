defmodule Dawarich.Tracks.Generation do
  @moduledoc false

  alias Dawarich.Tracks.{BoundaryWorker, ChunkWorker}

  @stalled "Max retries (5) exceeded waiting for chunks to complete"
  @insert_batch 1_000

  @exists "SELECT 1 FROM phoenix.track_generations WHERE id = $1"

  @insert """
  INSERT INTO phoenix.track_generations (id, user_id, mode, untracked_only, import_id, low_priority, status, total_chunks)
  VALUES ($1, $2, $3, $4, $5, $6, 'running', $7)
  ON CONFLICT (id) DO NOTHING RETURNING id
  """

  @insert_chunks """
  INSERT INTO phoenix.track_generation_chunks (generation_id, chunk_id, start_ts, end_ts, buffer_start_ts, buffer_end_ts)
  SELECT $1, c.* FROM unnest($2::int[], $3::bigint[], $4::bigint[], $5::bigint[], $6::bigint[]) AS c
  """

  @chunk_done """
  WITH done AS (
    UPDATE phoenix.track_generation_chunks SET status = 'completed', tracks_created = $3
    WHERE generation_id = $1 AND chunk_id = $2 AND status = 'pending'
    RETURNING generation_id, tracks_created
  )
  UPDATE phoenix.track_generations g
  SET completed_chunks = g.completed_chunks + 1, tracks_created = g.tracks_created + done.tracks_created, updated_at = now()
  FROM done WHERE g.id = done.generation_id
  RETURNING g.completed_chunks
  """

  @poll """
  UPDATE phoenix.track_generations
  SET poll_count = poll_count + 1,
      stall_count = CASE WHEN completed_chunks <= seen_completed THEN stall_count + 1 ELSE 0 END,
      seen_completed = completed_chunks, updated_at = now()
  WHERE id = $1 AND status = 'running' AND poll_count = $2 AND completed_chunks < total_chunks
  RETURNING stall_count
  """

  @complete """
  UPDATE phoenix.track_generations SET status = 'completed', updated_at = now()
  WHERE id = $1 AND status = 'running' AND completed_chunks >= total_chunks
  RETURNING id
  """

  @fail """
  UPDATE phoenix.track_generations SET status = 'failed', error = $2, updated_at = now()
  WHERE id = $1 AND status = 'running'
  RETURNING id
  """

  @get """
  SELECT user_id, low_priority, status, total_chunks, completed_chunks
  FROM phoenix.track_generations WHERE id = $1
  """

  @chunk """
  SELECT g.user_id, g.untracked_only, g.import_id, c.start_ts, c.end_ts, c.buffer_start_ts, c.buffer_end_ts
  FROM phoenix.track_generation_chunks c JOIN phoenix.track_generations g ON g.id = c.generation_id
  WHERE c.generation_id = $1 AND c.chunk_id = $2 AND c.status = 'pending'
  """

  def exists?(repo, id), do: rows(repo, @exists, [dump(id)]) != []

  def start!(repo, oban, args, chunks, opts \\ []) do
    hook = Keyword.get(opts, :hook, fn _stage -> :ok end)
    id = args["event_id"]
    priority = priority(args["low_priority"])
    total = length(chunks)

    {:ok, outcome} =
      repo.transaction(fn ->
        params = [
          dump(id),
          args["user_id"],
          args["mode"],
          args["untracked_only"],
          args["import_id"]
        ]

        case rows(repo, @insert, params ++ [args["low_priority"], total]) do
          [] ->
            :exists

          [_] ->
            rows(repo, @insert_chunks, [dump(id) | columns(chunks)])

            chunks
            |> Enum.map(
              &ChunkWorker.new(%{"generation_id" => id, "chunk_id" => &1.chunk_id},
                priority: priority
              )
            )
            |> Enum.chunk_every(Keyword.get(opts, :insert_batch, @insert_batch))
            |> Enum.each(&Oban.insert_all(oban, &1))

            Oban.insert!(
              oban,
              BoundaryWorker.new(%{"generation_id" => id, "poll_count" => 0},
                priority: priority,
                schedule_in: max(total * 30, 300)
              )
            )

            hook.(:inserted)
            :started
        end
      end)

    outcome
  end

  def get(repo, id) do
    case rows(repo, @get, [dump(id)]) do
      [[user_id, low_priority, status, total, completed]] ->
        %{
          id: id,
          user_id: user_id,
          low_priority: low_priority,
          status: status,
          total_chunks: total,
          completed_chunks: completed
        }

      [] ->
        nil
    end
  end

  def chunk(repo, id, chunk_id) do
    case rows(repo, @chunk, [dump(id), chunk_id]) do
      [[user_id, untracked_only, import_id, start_ts, end_ts, buffer_start_ts, buffer_end_ts]] ->
        %{
          user_id: user_id,
          untracked_only: untracked_only,
          import_id: import_id,
          start_ts: start_ts,
          end_ts: end_ts,
          buffer_start_ts: buffer_start_ts,
          buffer_end_ts: buffer_end_ts
        }

      [] ->
        nil
    end
  end

  def chunk_done!(repo, id, chunk_id, tracks_created) do
    case rows(repo, @chunk_done, [dump(id), chunk_id, tracks_created]) do
      [[completed]] -> completed
      [] -> nil
    end
  end

  def poll!(repo, oban, generation, poll_count) do
    {:ok, outcome} =
      repo.transaction(fn ->
        case rows(repo, @poll, [dump(generation.id), poll_count]) do
          [[stall_count]] when stall_count >= 5 ->
            fail!(repo, generation.id, @stalled)
            :failed

          [[_stall_count]] ->
            Oban.insert!(
              oban,
              BoundaryWorker.new(
                %{"generation_id" => generation.id, "poll_count" => poll_count + 1},
                priority: priority(generation.low_priority),
                schedule_in: min(30 * Integer.pow(2, min(poll_count, 4)), 300)
              )
            )

            :scheduled

          [] ->
            :missed
        end
      end)

    outcome
  end

  def complete!(repo, id), do: rows(repo, @complete, [dump(id)]) != []

  def fail!(repo, id, message), do: rows(repo, @fail, [dump(id), message]) != []

  defp columns(chunks),
    do:
      for(
        key <- [:chunk_id, :start_ts, :end_ts, :buffer_start_ts, :buffer_end_ts],
        do: Enum.map(chunks, &Map.fetch!(&1, key))
      )

  defp priority(true), do: 3
  defp priority(_), do: 0

  defp dump(id), do: Ecto.UUID.dump!(id)

  defp rows(repo, sql, params), do: repo.query!(sql, params, log: false).rows
end
