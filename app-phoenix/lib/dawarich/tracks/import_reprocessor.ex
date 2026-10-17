defmodule Dawarich.Tracks.ImportReprocessor do
  @moduledoc false
  require Logger
  alias Dawarich.Tracks.{Reprocessor, Settings, Store}

  def run(repo, import_id, opts \\ []) do
    tracks =
      Store.all(
        repo,
        "SELECT #{Store.columns()} FROM tracks t WHERE t.id IN (SELECT DISTINCT track_id FROM points WHERE import_id=$1 AND track_id IS NOT NULL) ORDER BY t.id",
        [import_id]
      )

    Enum.each(tracks, &reprocess(repo, &1, opts))
    length(tracks)
  end

  defp reprocess(repo, track, opts) do
    {:ok, _} =
      repo.transaction(fn ->
        user = Settings.find(repo, track.user_id)
        batch = opts |> Keyword.put(:fallback, true) |> Keyword.put(:callbacks, true)
        Reprocessor.reprocess!(repo, user, track, Keyword.get(opts, :now), batch)
      end)
  rescue
    error ->
      Logger.error("Failed to reprocess track #{track.id}: #{inspect(error.__struct__)}")
      if report = Keyword.get(opts, :report), do: report.(track.id, error)
  end
end
