defmodule Dawarich.Users.RecalculateWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 26

  alias Dawarich.Jobs.Processed
  alias Dawarich.State
  alias Dawarich.State.Lease
  alias Dawarich.Users.{Recalculation, RecalculationArgs, RecalculationNotifications}

  def args_from_command(version, payload),
    do: RecalculationArgs.decode("users.recalculate_data", version, payload)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}), do: run(Dawarich.Jobs.repo(), conf.name, args)

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: n}), do: Integer.pow(n - 1, 4) + 15 + (:rand.uniform(10) - 1) * n

  def run(repo, oban, args, opts \\ []) do
    key = "users.recalculate_data:" <> args["event_id"]

    case Lease.with_lease(
           repo,
           key,
           fn holder ->
             if Processed.done?(repo, args["event_id"]) do
               :ok
             else
               fence = fn -> fence!(repo, key, holder) end
               result = execute(repo, oban, args, fenced_options(opts, fence))
               settle(repo, args, result, opts, fence)
             end
           end,
           Keyword.get(opts, :lease, [])
         ) do
      {:ok, result} -> result
      {:error, :timeout} -> {:snooze, 3}
    end
  rescue
    error -> {:error, error}
  end

  defp execute(repo, oban, args, opts) do
    Recalculation.run(repo, oban, args, opts)
  rescue
    error -> {:failed, error, __STACKTRACE__}
  end

  def inline(repo, oban, args, fence, opts \\ []) do
    case execute(repo, oban, args, fenced_options(opts, fence)) do
      {:failed, error, stack} ->
        {:ok, _} =
          repo.transaction(fn ->
            fence.()
            RecalculationNotifications.create!(repo, args, :error, {error, stack})
          end)

        :erlang.raise(:error, error, stack)

      {:ok, result} ->
        {:ok, _} =
          repo.transaction(fn ->
            fence.()

            if result != :skipped,
              do: RecalculationNotifications.create!(repo, args, :success, result.years)

            fence.()
          end)

        :ok

      other ->
        other
    end
  end

  defp settle(repo, args, {:error, :lock_busy}, opts, fence) do
    {:ok, result} =
      repo.transaction(fn ->
        fence.()
        n = State.increment_cursor(repo, "users.recalculate_data:busy:" <> args["event_id"])

        if n < 5 do
          base = Integer.pow(n, 4)
          draw = Keyword.get_lazy(opts, :jitter_draw, &:rand.uniform/0)
          {:snooze, trunc(base + 2 + base * 0.15 * draw)}
        else
          terminal(repo, args, :busy, nil, opts, fence)
        end
      end)

    result
  end

  defp settle(repo, args, {:failed, error, stack}, _opts, fence) do
    {:ok, _} =
      repo.transaction(fn ->
        fence.()
        RecalculationNotifications.create!(repo, args, :error, {error, stack})
      end)

    {:error, error}
  end

  defp settle(repo, args, {:ok, result}, opts, fence) do
    {:ok, :ok} =
      repo.transaction(fn ->
        years = if result == :skipped, do: nil, else: result.years
        terminal(repo, args, :success, years, opts, fence)
      end)

    :ok
  end

  defp terminal(repo, args, kind, detail, opts, fence) do
    fence.()

    if Processed.claim!(repo, args["event_id"], "users.recalculate_data") do
      if kind == :busy or detail != nil,
        do: RecalculationNotifications.create!(repo, args, kind, detail)

      if fun = opts[:after_terminal], do: fun.()
      fence.()
    end

    :ok
  end

  defp fenced_options(opts, fence) do
    original = Keyword.get(opts, :before_month, fn _, _, _ -> :ok end)
    stats = Keyword.get(opts, :stats, &Dawarich.Stats.CalculateMonth.call/5)
    phase = Keyword.get(opts, :phase, fn _, _, _ -> :ok end)

    opts
    |> Keyword.put(:before_month, fn year, month, state ->
      original.(year, month, state)
      fence.()
    end)
    |> Keyword.put(:phase, fn kind, year, state ->
      fence.()
      phase.(kind, year, state)
      fence.()
    end)
    |> Keyword.put(:stats, fn repo, id, year, month, options ->
      fence.()
      result = stats.(repo, id, year, month, Keyword.put(options, :fence, fence))
      fence.()
      result
    end)
    |> Keyword.put(:digest_opts, digest_options(Keyword.get(opts, :digest_opts, []), fence))
    |> Keyword.put(:range_opts, range_options(Keyword.get(opts, :range_opts, []), fence))
  end

  defp range_options(options, fence) do
    hook = Keyword.get(options, :hook, fn _ -> :ok end)

    options
    |> Keyword.put(:fence, fence)
    |> Keyword.put(:hook, fn stage ->
      fence.()
      hook.(stage)
      fence.()
    end)
  end

  defp digest_options(options, fence) do
    Enum.reduce([:before_store, :after_store], options, fn key, acc ->
      original = Keyword.get(options, key, fn _ -> :ok end)

      Keyword.put(acc, key, fn value ->
        fence.()
        original.(value)
        fence.()
      end)
    end)
  end

  defp fence!(repo, key, holder) do
    case repo.query!(
           "SELECT holder,expires_at>statement_timestamp() FROM phoenix.leases WHERE name=$1 FOR UPDATE",
           [key],
           log: false
         ).rows do
      [[^holder, true]] -> :ok
      _ -> raise "recalculation lease lost"
    end
  end
end
