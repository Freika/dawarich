defmodule Dawarich.Tracks.MapMatching.Sweeper do
  use Oban.Worker, queue: :map_matching, max_attempts: 1

  alias Dawarich.Tracks.MapMatching.Enqueuer

  @impl Oban.Worker
  def perform(%Oban.Job{conf: conf}), do: run(conf.repo)

  def run(repo) do
    cutoff = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_iso8601()
    if Dawarich.Experimental.map_matching?(repo), do: sweep(repo, cutoff, 0), else: :ok
  end

  defp sweep(repo, cutoff, last) do
    ids =
      repo.query!(
        """
        SELECT id FROM tracks WHERE id>$1 AND (
          (map_matching_status=0 AND map_matching_data->>'claimed_at' <= $2)
          OR map_matching_status IS DISTINCT FROM 0)
          AND demo IS NOT TRUE
        ORDER BY id LIMIT 500
        """,
        [last, cutoff],
        log: false
      ).rows
      |> List.flatten()

    Enum.each(ids, &Enqueuer.call(repo, &1))
    if length(ids) == 500, do: sweep(repo, cutoff, List.last(ids)), else: :ok
  end
end
