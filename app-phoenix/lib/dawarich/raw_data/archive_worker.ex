defmodule Dawarich.RawData.ArchiveWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :maintenance,
    priority: 3,
    max_attempts: 3,
    unique: [keys: [:user_id], states: [:available, :scheduled], period: :infinity]

  alias Dawarich.RawData.{ArchiveFormat, Archiver, Archives, UserSweep}
  alias Dawarich.{ReleaseOperations, Storage}

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

    if ReleaseOperations.user?(repo, user_id) do
      Archives.recover!(repo, storage, user_id)

      with {:continue, next} <- Archiver.pass(repo, storage, key, user_id, cursor, opts) do
        Oban.insert!(oban, new(%{"user_id" => user_id, "cursor" => next}))
      end
    end

    :ok
  end

  def run(repo, oban, args, opts) when args == %{},
    do: UserSweep.run(repo, oban, @key, &new(%{"user_id" => &1, "cursor" => 0}), opts)

  def run(_repo, _oban, _args, _opts), do: {:cancel, :invalid_args}
end
