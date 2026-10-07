defmodule Dawarich.AfterCommit do
  @moduledoc false

  def enqueue(repo, worker, args, opts \\ []) do
    repo.insert!(worker.new(args, opts), prefix: "oban", log: false)
    :ok
  end

  def cache(repo, operation, payload) do
    enqueue(repo, Dawarich.AfterCommit.Worker, %{
      "operation" => operation,
      "payload" => payload,
      "intent_id" => Ecto.UUID.generate()
    })
  end

  def once(repo, intent, effect),
    do: Dawarich.Jobs.Processed.once(repo, intent, "after_commit", effect)
end
