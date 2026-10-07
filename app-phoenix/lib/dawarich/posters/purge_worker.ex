defmodule Dawarich.Posters.PurgeWorker do
  @moduledoc false
  use Oban.Worker, queue: :posters, max_attempts: 26
  alias Dawarich.Jobs.Processed
  alias Dawarich.Storage.NativePurge

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def prepare!(repo, args) do
    objects =
      if repo.query!("SELECT id FROM posters WHERE id=$1", [args["poster_id"]], log: false).rows ==
           [],
         do: NativePurge.collect(repo, args["blob_ids"]),
         else: []

    NativePurge.mark!(repo, objects)
    Map.put(args, "objects", objects)
  end

  def run(repo, args, opts \\ []) do
    if Processed.done?(repo, args["event_id"]) do
      :ok
    else
      {:ok, args} =
        repo.transaction(fn ->
          if Map.has_key?(args, "objects"), do: args, else: prepare!(repo, args)
        end)

      result =
        if repo.query!("SELECT id FROM posters WHERE id=$1", [args["poster_id"]], log: false).rows ==
             [],
           do: Dawarich.Exports.PurgeWorker.run(args, Keyword.put(opts, :repo, repo)),
           else: :ok

      case result do
        :ok -> Processed.mark!(repo, args["event_id"], "posters.purge")
        error -> error
      end
    end
  end
end
