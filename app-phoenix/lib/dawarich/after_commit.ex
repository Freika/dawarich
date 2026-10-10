defmodule Dawarich.AfterCommit do
  @moduledoc false

  def identity(root, name) do
    root = if is_integer(root), do: "user:#{root}", else: Ecto.UUID.dump!(root)
    <<a::48, _::4, b::12, _::2, c::62, _::binary>> = :crypto.hash(:sha, root <> name)
    Ecto.UUID.load!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end

  def intent(repo, command, payload, opts) do
    if repo.in_transaction?() do
      with {:ok, worker} <- command_worker(command),
           {:ok, _args} <- worker.args_from_command(1, payload),
           :oban <- Dawarich.Jobs.Ownership.lock(repo, "command:" <> command) do
        publish_intent(repo, command, payload, opts)
      else
        {:error, _} = error -> error
        _ -> {:error, :callback_owner}
      end
    else
      {:error, :transaction_required}
    end
  end

  defp command_worker(command) do
    case Dawarich.Jobs.Registry.command(command) do
      :error -> {:error, "unknown_command"}
      worker -> worker
    end
  end

  defp publish_intent(repo, command, payload, opts) do
    event = Keyword.fetch!(opts, :event_id)
    aggregate = Keyword.get(opts, :aggregate_id, payload["user_id"])

    if aggregate do
      repo.query!("SELECT id FROM public.users WHERE id=$1 FOR UPDATE", [aggregate], log: false)
    end

    repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", [event], log: false)

    unless Dawarich.Jobs.Processed.done?(repo, event) do
      repo.query!(
        "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,aggregate_id,dedupe_key,metadata,scheduled_at) " <>
          "VALUES($1,$2,1,$3,$4,$5,$6,$7) ON CONFLICT DO NOTHING",
        [
          Ecto.UUID.dump!(event),
          command,
          payload,
          aggregate,
          Keyword.get(opts, :dedupe_key, event),
          %{"producer" => "phoenix.after_commit"},
          Keyword.get_lazy(opts, :scheduled_at, &DateTime.utc_now/0)
        ],
        log: false
      )
    end

    :ok
  end

  def enqueue(repo, worker, args, opts \\ []) do
    {:ok, :ok} =
      transaction(repo, fn ->
        if worker in [Dawarich.Points.TileEpochWorker, Dawarich.Points.VisitMonthsWorker],
          do: Dawarich.AfterCommit.Visibility.record(repo, "keys", args)

        repo.insert!(worker.new(args, opts), prefix: "oban", log: false)
        :ok
      end)

    :ok
  end

  def cache(repo, operation, payload) do
    {:ok, :ok} =
      transaction(repo, fn ->
        payload =
          if operation == "tracks",
            do: Dawarich.Tracks.NativeChanges.snapshot(repo, payload),
            else: payload

        Dawarich.AfterCommit.Visibility.record(repo, operation, payload)

        enqueue(repo, Dawarich.AfterCommit.Worker, %{
          "operation" => operation,
          "payload" => payload,
          "intent_id" => Ecto.UUID.generate()
        })
      end)

    :ok
  end

  def with_visibility(repo, operation, payload, effect) do
    {:ok, result} =
      transaction(repo, fn ->
        Dawarich.AfterCommit.Visibility.record(repo, operation, payload)
        effect.()
      end)

    result
  end

  defp transaction(repo, effect) do
    if function_exported?(repo, :in_transaction?, 0) and repo.in_transaction?(),
      do: {:ok, effect.()},
      else: repo.transaction(effect)
  end

  def once(repo, intent, effect),
    do:
      Dawarich.Jobs.Processed.once(repo, intent, "after_commit", fn ->
        Dawarich.Cable.Delivery.with_intent(intent, effect)
      end)
end
