defmodule Dawarich.Exports.PointsWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :exports,
    max_attempts: 3,
    unique: [keys: [:export_id], states: :incomplete, period: :infinity]

  alias Dawarich.{Exports, Storage}

  def args_from_command(1, %{"export_id" => export_id, "user_id" => user_id} = payload)
      when is_integer(export_id) and is_integer(user_id) and map_size(payload) == 2,
      do: {:ok, %{"export_id" => export_id, "user_id" => user_id}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(55)

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"event_id" => event_id, "export_id" => export_id, "user_id" => user_id}
      }) do
    repo = Dawarich.Jobs.repo()

    case Exports.claim(repo, export_id, user_id, event_id) do
      :skip -> :ok
      {:run, export} -> run(repo, export, event_id)
    end
  end

  defp run(repo, export, event_id) do
    case prepare(repo, export, event_id) do
      :failed -> :ok
      {config, dir} -> generate(repo, config, dir, export, event_id)
    end
  end

  defp prepare(repo, export, event_id) do
    config = Storage.config!(System.get_env())
    Storage.sweep_tmp(config, 86_400)
    {config, Storage.tmp_dir!(config, event_id)}
  rescue
    error ->
      Exports.fail!(
        repo,
        export,
        event_id,
        Exception.message(error),
        Exports.failure_notification(export, error)
      )

      :failed
  end

  defp generate(repo, config, dir, export, event_id) do
    outcome =
      try do
        zip =
          Exports.Points.write_zip!(
            repo,
            export,
            dir,
            System.get_env("TIME_ZONE", "Europe/Berlin")
          )

        {:ok, Storage.put!(config, zip, export.name <> ".zip", "application/zip")}
      rescue
        error -> {:failed, error}
      end

    case outcome do
      {:ok, blob} ->
        finish(repo, config, export, event_id, blob)

      {:failed, error} ->
        Exports.fail!(
          repo,
          export,
          event_id,
          Exception.message(error),
          Exports.failure_notification(export, error)
        )
    end
  after
    File.rm_rf(dir)
  end

  defp finish(repo, config, export, event_id, blob) do
    case Exports.complete(repo, export, event_id, blob, Exports.success_notification(export)) do
      :ok -> :ok
      :lost -> Storage.delete(config, blob.key)
    end
  rescue
    error ->
      _ = Storage.delete(config, blob.key)
      reraise error, __STACKTRACE__
  end
end
