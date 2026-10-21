defmodule Dawarich.Imports.Trek.WorkerState do
  @moduledoc false
  alias Dawarich.Imports.Trek.{Sync, Client}
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.State.Lease

  def run(repo, args, type, opts, fun) do
    if Processed.done?(repo, args["event_id"]) do
      :ok
    else
      case Lease.with_lease(
             repo,
             "trek-sync:#{args["source_id"]}",
             fn holder ->
               case capture(repo, args, type, opts, holder) do
                 {:ok, ctx} when is_map(ctx) -> fun.(ctx)
                 {:ok, :skip} -> :ok
                 {:error, :lost} -> {:cancel, :ownership_lost}
               end
             end,
             timeout_ms: 0
           ) do
        {:ok, result} -> result
        {:error, :timeout} -> busy(repo, args, type, opts)
      end
    end
  end

  defp capture(repo, args, type, opts, holder) do
    repo.transaction(fn ->
      key = "command:" <> type
      if Ownership.lock(repo, key) != :oban, do: repo.rollback(:lost)
      if Processed.done?(repo, args["event_id"]), do: repo.rollback(:lost)

      [[stamp]] =
        repo.query!("SELECT updated_at FROM phoenix.job_owners WHERE key=$1", [key], log: false).rows

      ctx = Sync.context(repo, args["source_id"], opts)
      if is_nil(ctx) or ctx.status != 0, do: repo.rollback(:lost)
      Sync.current!(ctx)
      importing = type == "imports.trek_import"

      if ctx.importing != importing or
           (importing and ctx.selection_token != args["selection_token"]),
         do: repo.rollback(:lost)

      if allowed?(repo, ctx, opts) do
        base = Map.merge(ctx, %{holder: holder, key: key, stamp: stamp, args: args, type: type})
        %{base | opts: Keyword.put(opts, :fence, fn -> fence!(base) end)}
      else
        if importing, do: Sync.update_source!(ctx, %{importing: false})
        Processed.mark!(repo, args["event_id"], key)
        :skip
      end
    end)
  end

  def fence!(ctx) do
    if Ownership.lock(ctx.repo, ctx.key) != :oban, do: ctx.repo.rollback(:lost)

    [[stamp]] =
      ctx.repo.query!("SELECT updated_at FROM phoenix.job_owners WHERE key=$1", [ctx.key],
        log: false
      ).rows

    lease =
      ctx.repo.query!(
        "SELECT holder,expires_at>statement_timestamp() FROM phoenix.leases WHERE name=$1 FOR UPDATE",
        ["trek-sync:#{ctx.id}"],
        log: false
      ).rows

    if stamp != ctx.stamp or lease != [[ctx.holder, true]] or
         not allowed?(ctx.repo, ctx, ctx.opts),
       do: ctx.repo.rollback(:lost)

    Sync.current!(%{ctx | opts: Keyword.delete(ctx.opts, :fence)})
  end

  def allowed?(repo, ctx, opts) do
    case repo.query!(
           "SELECT plan FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
           [ctx.user_id],
           log: false
         ).rows do
      [[plan]] ->
        Dawarich.Entitlements.full_access?(
          repo,
          %{id: ctx.user_id, plan: plan},
          Keyword.get_lazy(opts, :self_hosted?, &Dawarich.ReleaseMigration.self_hosted?/0),
          ctx.now
        )

      [] ->
        false
    end
  end

  def finish(ctx, fun) do
    case ctx.repo.transaction(fn ->
           Sync.current!(ctx)
           fun.()
           Processed.mark!(ctx.repo, ctx.args["event_id"], ctx.key)
         end) do
      {:ok, _} -> :ok
      {:error, :lost} -> {:cancel, :ownership_lost}
    end
  end

  def fail(ctx, error) do
    terminal =
      not is_struct(error, Client.Error) or error.kind == :decryption or error.status == 401 or
        ((ctx.opts[:job] && ctx.opts[:job].attempt) || 1) >= 5

    result =
      ctx.repo.transaction(fn ->
        Sync.current!(ctx)
        attrs = if is_struct(error, Client.Error), do: %{last_error: error.message}, else: %{}

        attrs =
          if is_struct(error, Client.Error) and error.status == 401,
            do: Map.put(attrs, :status, 1),
            else: attrs

        attrs =
          if terminal and ctx.type == "imports.trek_import",
            do: Map.put(attrs, :importing, false),
            else: attrs

        if attrs != %{}, do: Sync.update_source!(ctx, attrs)
        if terminal, do: Processed.mark!(ctx.repo, ctx.args["event_id"], ctx.key)
      end)

    case result do
      {:error, :lost} -> {:cancel, :ownership_lost}
      {:ok, _} when terminal -> {:discard, error}
      {:ok, _} -> {:error, error}
    end
  end

  def enqueue!(ctx, payload) do
    ctx.repo.query!(
      "INSERT INTO job_outbox(event_id,command_type,command_version,payload,aggregate_id,metadata,scheduled_at) VALUES($1,$2,1,$3,$4,$5,$6)",
      [
        Ecto.UUID.dump!(Ecto.UUID.generate()),
        ctx.type,
        payload,
        ctx.id,
        %{"producer" => "Trek continuation"},
        DateTime.add(ctx.now, 60, :second)
      ],
      log: false
    )
  end

  defp busy(repo, args, "imports.trek_import" = type, opts) do
    case capture(repo, args, type, opts, nil) do
      {:ok, ctx} when is_map(ctx) ->
        case repo.transaction(fn ->
               if Ownership.lock(repo, ctx.key) != :oban, do: repo.rollback(:lost)

               [[stamp]] =
                 repo.query!("SELECT updated_at FROM phoenix.job_owners WHERE key=$1", [ctx.key],
                   log: false
                 ).rows

               if stamp != ctx.stamp, do: repo.rollback(:lost)
               Sync.current!(%{ctx | opts: Keyword.delete(ctx.opts, :fence)})
               enqueue!(ctx, Map.drop(args, ["event_id"]))
               Processed.mark!(repo, args["event_id"], ctx.key)
             end) do
          {:ok, _} -> :ok
          {:error, :lost} -> {:cancel, :ownership_lost}
        end

      {:ok, :skip} ->
        :ok

      {:error, :lost} ->
        {:cancel, :ownership_lost}
    end
  end

  defp busy(_repo, _args, _type, _opts), do: :ok

  def backoff(job) do
    delay = :math.pow(job.attempt, 4)
    trunc(delay + 2 + :rand.uniform() * 0.15 * delay)
  end
end
