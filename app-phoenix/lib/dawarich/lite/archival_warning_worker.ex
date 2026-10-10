defmodule Dawarich.Lite.ArchivalWarningWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  alias Dawarich.Jobs.Ownership
  alias Dawarich.Lite.ArchivalWarnings
  alias Dawarich.{ReleaseMigration, TimeZoneName}

  @key "cron:lite_archival_warning_job"
  @mail_key "command:mail.user.archival_approaching"
  @batch_size 100
  @batch "SELECT id FROM users WHERE plan = 0 AND deleted_at IS NULL AND id > $1 ORDER BY id LIMIT #{@batch_size}"

  def key, do: @key

  @impl Oban.Worker
  def perform(%Oban.Job{conf: conf}),
    do: run(Dawarich.Jobs.repo(), conf.name, DateTime.utc_now())

  def run(repo, oban, now, tz \\ System.get_env("TIME_ZONE", "Europe/Berlin")) do
    if ReleaseMigration.self_hosted?(),
      do: :ok,
      else: scan(repo, oban, TimeZoneName.to_iana(tz), now, 0)
  end

  defp scan(repo, oban, tz, now, after_id) do
    ids = repo.query!(@batch, [after_id], log: false).rows |> List.flatten()

    case Enum.reduce_while(ids, :ok, fn id, :ok -> check(repo, oban, tz, now, id) end) do
      :ok when length(ids) == @batch_size -> scan(repo, oban, tz, now, List.last(ids))
      result -> result
    end
  end

  defp check(repo, oban, tz, now, user_id) do
    case repo.transaction(fn ->
           case Ownership.lock(repo, @key) do
             :oban ->
               mail_owned? = Ownership.lock(repo, @mail_key) == :oban
               ArchivalWarnings.check_user(repo, tz, user_id, mail_owned?, oban, now)

             _ ->
               :not_owner
           end
         end) do
      {:ok, :not_owner} -> {:halt, {:cancel, :not_owner}}
      {:ok, _} -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end
end
