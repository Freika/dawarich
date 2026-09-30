defmodule Dawarich.EnhancedImport.DestroyGpxWorker do
  @moduledoc false
  use Oban.Worker, queue: :extractions, max_attempts: 26

  alias Dawarich.EnhancedImport.State

  @batch 500
  @owned "WHERE user_id = $1 AND import_id = $2"
  @owns_work "SELECT EXISTS (SELECT 1 FROM visits #{@owned}) OR EXISTS (SELECT 1 FROM tracks #{@owned})"
  @deletes [
    "UPDATE visits SET place_id = NULL WHERE place_id = ANY($1)",
    "DELETE FROM place_visits WHERE place_id = ANY($1)",
    "DELETE FROM taggings WHERE taggable_type = 'Place' AND taggable_id = ANY($1)",
    "DELETE FROM notes WHERE attachable_type = 'Place' AND attachable_id = ANY($1)",
    "DELETE FROM places WHERE id = ANY($1)"
  ]

  def args_from_command(1, %{"import_id" => id} = p) when is_integer(id) and map_size(p) == 1,
    do: {:ok, p}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: run(Dawarich.Jobs.repo(), job)

  def run(repo, %Oban.Job{args: %{"import_id" => id}}) do
    case State.load(repo, id) do
      nil -> :ok
      import -> destroy(repo, import)
    end
  end

  defp destroy(repo, import) do
    params = [import.user_id, import.id]
    ids = column(repo, "SELECT id FROM places " <> @owned, params)

    if column(repo, @owns_work, params) == [true],
      do: raise("extracted visits or tracks present")

    referenced =
      column(repo, "SELECT DISTINCT place_id FROM visits WHERE place_id = ANY($1)", [ids])

    (ids -- referenced)
    |> Enum.sort()
    |> Enum.chunk_every(@batch)
    |> Enum.each(&delete_batch!(repo, &1))

    State.reset!(repo, import)
    :ok
  rescue
    exception ->
      State.destroy_failed!(repo, import, Exception.message(exception))
      reraise exception, __STACKTRACE__
  end

  defp delete_batch!(repo, ids) do
    {:ok, :ok} =
      repo.transaction(fn -> Enum.each(@deletes, &repo.query!(&1, [ids], log: false)) end)
  end

  defp column(repo, sql, params),
    do: repo.query!(sql, params, log: false).rows |> Enum.map(&hd/1)
end
