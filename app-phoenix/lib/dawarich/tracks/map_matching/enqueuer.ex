defmodule Dawarich.Tracks.MapMatching.Enqueuer do
  alias Dawarich.{ErrorReporting, Experimental}
  alias Dawarich.MapMatching.{Fingerprint, Input, Processor}
  alias Dawarich.Tracks.MapMatching.{State, Worker}

  def defer(repo, track_id) do
    if Experimental.pinned?(:map_matching_enabled) and
         Experimental.value(:map_matching_enabled, repo) != true,
       do: :disabled,
       else: Dawarich.Tracks.MapMatching.Deferred.call(repo, track_id)
  end

  def call(repo, track_id) do
    if Experimental.map_matching?(repo) do
      {:ok, result} = repo.transaction(fn -> claim(repo, track_id) end)
      result
    else
      :disabled
    end
  rescue
    _ ->
      report(track_id)
      :error
  end

  defp claim(repo, id) do
    case repo.query!("SELECT demo FROM tracks WHERE id=$1 FOR UPDATE", [id], log: false).rows do
      [[false]] -> prepare(repo, id)
      _ -> :skip
    end
  end

  defp prepare(repo, id) do
    input = Input.load(repo, id)
    digest = Fingerprint.call(input)
    state = State.read(repo, id)

    state =
      if state.digest != digest do
        State.write!(repo, id, %{
          status: nil,
          digest: digest,
          matched_path: nil,
          data: %{},
          matched_at: nil
        })

        State.read(repo, id)
      else
        state
      end

    cond do
      not Input.eligible?(input) -> skipped(repo, id, digest, input, state)
      State.result?(state) or live?(state) -> :current
      true -> enqueue(repo, id, digest)
    end
  end

  defp live?(%{status: :pending, data: %{"claimed_at" => at}}) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, stamp, _} -> DateTime.diff(DateTime.utc_now(), stamp) < 3600
      _ -> false
    end
  end

  defp live?(_), do: false

  defp skipped(_repo, _id, _digest, _input, %{status: :skipped}), do: :skip

  defp skipped(repo, id, digest, input, _state) do
    result = Processor.skipped(input)

    State.write!(repo, id, %{
      status: :skipped,
      digest: digest,
      matched_path: nil,
      data: result.data,
      matched_at: DateTime.utc_now()
    })

    :skip
  end

  defp enqueue(repo, id, digest) do
    repo.query!("SAVEPOINT map_matching_claim", [], log: false)

    try do
      insert(repo, id, digest)
      repo.query!("RELEASE SAVEPOINT map_matching_claim", [], log: false)
      :enqueued
    rescue
      _ ->
        repo.query!("ROLLBACK TO SAVEPOINT map_matching_claim", [], log: false)
        repo.query!("RELEASE SAVEPOINT map_matching_claim", [], log: false)
        State.write!(repo, id, %{data: %{enqueue_failed: true}})
        report(id)
        :error
    end
  end

  defp insert(repo, id, digest) do
    oban = Application.get_env(:dawarich, :map_matching_oban, Oban)
    if Oban.config(oban).repo != repo, do: raise(ArgumentError, "Map matching repo mismatch")

    State.write!(repo, id, %{
      status: :pending,
      digest: digest,
      data: %{claimed_at: DateTime.to_iso8601(DateTime.utc_now())},
      matched_at: nil
    })

    if repo.query!(
         "SELECT id FROM oban.oban_jobs WHERE worker=$1 AND args->>'track_id'=$2 AND args->>'digest'=$3 AND state IN ('available','scheduled','executing','retryable') LIMIT 1",
         [inspect(Worker), to_string(id), digest],
         log: false
       ).rows == [] do
      Oban.insert!(oban, Worker.new(%{track_id: id, digest: digest}, unique: false), retry: false)
    end

    :ok
  end

  defp report(id),
    do:
      ErrorReporting.capture_release(
        :error,
        RuntimeError.exception("map_matching.enqueue_failed track_id=#{id}"),
        []
      )
end
