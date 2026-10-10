defmodule Dawarich.Families.EventsWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :projections,
    max_attempts: 20,
    unique: [keys: [:event_id], states: :all, period: :infinity]

  @kinds %{
    "membership" => :membership,
    "consent" => :consent,
    "request" => :request,
    "invitation" => :invitation,
    "lapse" => :lapse,
    "location" => :location
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, args) do
    if repo.in_transaction?(),
      do: raise(ArgumentError, "family invalidation requires committed intent")

    with {:ok, kind} <- Map.fetch(@kinds, args["kind"]) do
      Dawarich.AfterCommit.once(repo, args["event_id"], fn ->
        Dawarich.Families.Events.broadcast(args["user_id"], kind)
      end)
    end
  end
end
