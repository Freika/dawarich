defmodule Dawarich.Families.InvitationCleanupWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  require Logger

  alias Dawarich.Families
  alias Dawarich.Jobs.Ownership

  @key "cron:nightly_family_invitations_cleanup_job"

  def key, do: @key

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run(Dawarich.Jobs.repo(), NaiveDateTime.utc_now())

  def run(repo, now) do
    case Ownership.with_owner(repo, @key, :oban, fn -> Families.expire_invitations(repo, now) end) do
      {:ok, {expired, deleted}} ->
        Logger.info("family invitations: #{expired} expired, #{deleted} deleted")
        :ok

      {:skip, _owner} ->
        {:cancel, :not_owner}
    end
  end
end
