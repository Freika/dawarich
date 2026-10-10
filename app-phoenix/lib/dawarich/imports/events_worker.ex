defmodule Dawarich.Imports.EventsWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :projections,
    max_attempts: 20,
    unique: [keys: [:event_id], states: :all, period: :infinity]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, args) do
    if repo.in_transaction?(),
      do: raise(ArgumentError, "import notification requires a committed intent")

    Dawarich.AfterCommit.once(repo, args["event_id"], fn ->
      Dawarich.Imports.Events.broadcast(args["user_id"])
    end)
  end
end
