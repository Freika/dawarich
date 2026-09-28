defmodule Dawarich.Jobs.Dispatch do
  @moduledoc false

  require Logger

  alias Dawarich.Jobs.{Outbox, Registry}

  def run(opts) do
    repo = Keyword.fetch!(opts, :repo)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    if Outbox.due?(repo, now), do: dispatch(repo, now, opts), else: %{}
  end

  defp dispatch(repo, now, opts) do
    context = %{
      repo: repo,
      now: now,
      oban: Keyword.get(opts, :oban, Oban),
      commands: Keyword.get(opts, :commands, &Registry.command/1),
      hook: Keyword.get(opts, :hook, fn _stage, _row -> :ok end)
    }

    {:ok, counts} =
      repo.transaction(fn ->
        repo
        |> Outbox.claim_due(now, Keyword.get(opts, :limit, 100))
        |> Enum.map(&deliver(context, &1))
        |> Enum.frequencies()
      end)

    counts
  end

  defp deliver(context, row) do
    context.hook.(:claimed, row)

    with {:ok, changeset} <- changeset(context.commands, row),
         {:ok, job} <- insert(context.oban, changeset) do
      context.hook.(:inserted, row)

      Outbox.update_delivery!(context.repo, row.event_id,
        state: "dispatched",
        oban_job_id: job.id,
        dispatched_at: context.now,
        error_code: if(job.id, do: nil, else: "deduped_locked")
      )

      context.hook.(:acknowledged, row)
      :dispatched
    else
      {:error, code} ->
        Outbox.update_delivery!(context.repo, row.event_id,
          state: "quarantined",
          error_code: code
        )

        :quarantined
    end
  end

  defp changeset(commands, row) do
    with {:ok, worker} <- lookup(commands, row.command_type),
         {:ok, args} <- worker.args_from_command(row.command_version, row.payload) do
      args = Map.put(args, "event_id", row.event_id)
      _ = Jason.encode_to_iodata!(args)
      {:ok, worker.new(args, meta: %{"command_version" => row.command_version})}
    end
  rescue
    exception ->
      Logger.warning(
        "job_outbox #{row.event_id} (#{row.command_type}) quarantined as decoder_error: " <>
          inspect(exception.__struct__)
      )

      {:error, "decoder_error"}
  end

  defp lookup(commands, type) do
    case commands.(type) do
      {:ok, worker} -> {:ok, worker}
      :error -> {:error, "unknown_command"}
    end
  end

  defp insert(oban, changeset) do
    case Oban.insert(oban, changeset, retry: false) do
      {:ok, job} -> {:ok, job}
      {:error, _invalid} -> {:error, "invalid_job"}
    end
  end
end
