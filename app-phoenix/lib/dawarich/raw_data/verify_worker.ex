defmodule Dawarich.RawData.VerifyWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :maintenance,
    priority: 3,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  require Logger

  alias Dawarich.Jobs.Ownership
  alias Dawarich.RawData.{ArchiveFormat, Verifier}
  alias Dawarich.{ReleaseOperations, Storage}

  @key "cron:raw_data_verify_job"
  @sample "SELECT id FROM points_raw_data_archives ORDER BY random() LIMIT 10"

  def key, do: @key

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run(Dawarich.Jobs.repo())

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(20)

  def run(repo, opts \\ []) do
    case Ownership.with_owner(repo, @key, :oban, fn -> :owned end) do
      {:ok, :owned} -> verify_sample(repo, opts)
      {:skip, _owner} -> {:cancel, :not_owner}
    end
  end

  defp verify_sample(repo, opts) do
    storage = Keyword.get_lazy(opts, :storage, fn -> Storage.config!(System.get_env()) end)
    key = Keyword.get_lazy(opts, :archive_key, &ArchiveFormat.key/0)

    for id <- ReleaseOperations.ids(repo, @sample, []) do
      try do
        Verifier.verify(repo, storage, key, id)
      rescue
        error -> Logger.error("Failed to verify archive #{id}: #{Exception.message(error)}")
      end
    end

    :ok
  end
end
