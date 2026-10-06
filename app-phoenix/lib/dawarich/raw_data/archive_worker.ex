defmodule Dawarich.RawData.ArchiveWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :maintenance,
    priority: 3,
    max_attempts: 3,
    unique: [keys: [:user_id, :cursor], states: [:available, :scheduled], period: :infinity]

  alias Dawarich.RawData.{ArchiveFormat, Archiver, Archives, UserSweep}
  alias Dawarich.{ReleaseOperations, Storage}
  alias Dawarich.State.Lease

  @key "cron:raw_data_archive_job"

  def key, do: @key

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}), do: run(Dawarich.Jobs.repo(), conf.name, args)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(20)

  def run(repo, oban, args, opts \\ [])

  def run(repo, oban, %{"user_id" => user_id, "cursor" => cursor}, opts)
      when is_integer(user_id) and is_integer(cursor) do
    storage = Keyword.get_lazy(opts, :storage, fn -> Storage.config!(System.get_env()) end)
    key = Keyword.get_lazy(opts, :archive_key, &ArchiveFormat.key/0)

    result =
      if ReleaseOperations.user?(repo, user_id) do
        Lease.with_lease(
          repo,
          "archive_raw_data:#{user_id}",
          fn ->
            Archives.recover!(repo, storage, user_id)
            Archiver.pass(repo, storage, key, user_id, cursor, opts)
          end,
          timeout_ms: 0
        )
      end

    with {:ok, {:continue, next}} <- result do
      Oban.insert!(oban, new(%{"user_id" => user_id, "cursor" => next}))
    end

    :ok
  end

  def run(repo, oban, args, opts) when args == %{},
    do: UserSweep.run(repo, oban, @key, &new(%{"user_id" => &1, "cursor" => 0}), opts)

  def run(_repo, _oban, _args, _opts), do: {:cancel, :invalid_args}
end
