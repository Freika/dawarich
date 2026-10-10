defmodule Dawarich.Sharing.EventsWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :projections,
    max_attempts: 20,
    unique: [keys: [:event_id], states: :all, period: :infinity]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, args) do
    if repo.in_transaction?(),
      do: raise(ArgumentError, "sharing invalidation requires committed intent")

    Dawarich.AfterCommit.once(repo, args["event_id"], fn ->
      user = args["user_id"]

      Phoenix.PubSub.broadcast(
        Dawarich.PubSub,
        "sharing:user:#{user}",
        {:domain_changed, user, :sharing}
      )

      for id <- args["public_ids"] do
        Phoenix.PubSub.broadcast(
          Dawarich.PubSub,
          "sharing:public:#{id}",
          {:share_changed, id, Dawarich.Sharing.version(id)}
        )
      end

      :ok
    end)
  end
end
