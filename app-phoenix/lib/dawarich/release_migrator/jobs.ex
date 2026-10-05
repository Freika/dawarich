defmodule Dawarich.ReleaseMigrator.Jobs do
  @moduledoc false

  def insert!(repo, version, {class, args, wait}, mode)
      when is_binary(class) and is_list(args) and is_integer(wait) and wait >= 0 do
    changeset = changeset(class, args, wait, mode)

    repo.query!(
      "INSERT INTO phoenix.release_migration_jobs (version, job_class, arguments, wait_seconds) VALUES ($1, $2, $3, $4)",
      [version, class, args, wait],
      log: false
    )

    if changeset, do: repo.insert!(changeset, prefix: "oban", log: false)
    :ok
  end

  def insert!(_repo, _version, job, _mode) do
    raise ArgumentError, "malformed job #{inspect(job)}; expected {class, args, wait_seconds}"
  end

  defp changeset(_class, _args, _wait, :record), do: nil

  defp changeset(class, args, wait, :enqueue) do
    case Dawarich.ReleaseJobs.decode(class, args) do
      {:ok, worker, payload} ->
        worker.new(payload, schedule_in: wait)

      :skip ->
        nil

      {:deferred, owner, _payload} ->
        raise ArgumentError, "release job #{class} deferred to #{owner}"

      {:error, reason} ->
        raise ArgumentError, "release job #{class} refused: #{reason}"
    end
  end
end
