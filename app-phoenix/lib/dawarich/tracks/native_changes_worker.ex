defmodule Dawarich.Tracks.NativeChangesWorker do
  @moduledoc false
  use Oban.Worker, queue: :tracks, max_attempts: 20

  alias Dawarich.Tracks.NativeChanges

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, payload) do
    NativeChanges.bump(payload)
    {:ok, :ok} = repo.transaction(fn -> NativeChanges.publish!(repo, payload) end)
    :ok
  end
end
