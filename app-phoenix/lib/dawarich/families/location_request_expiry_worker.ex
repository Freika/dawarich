defmodule Dawarich.Families.LocationRequestExpiryWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  require Logger

  alias Dawarich.Families
  alias Dawarich.Jobs.Ownership

  @key "cron:family_location_requests_expiry_job"

  def key, do: @key

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run(Dawarich.Jobs.repo(), NaiveDateTime.utc_now())

  def run(repo, now) do
    case Ownership.with_owner(repo, @key, :oban, fn ->
           Families.expire_location_requests(repo, now)
         end) do
      {:ok, expired} ->
        Logger.info("family location requests: #{expired} expired")
        :ok

      {:skip, _owner} ->
        {:cancel, :not_owner}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
