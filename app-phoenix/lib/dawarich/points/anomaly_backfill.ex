defmodule Dawarich.Points.AnomalyBackfill do
  @moduledoc false

  alias Dawarich.Points.AnomalyFilter
  alias Dawarich.RailsCommands
  alias Dawarich.State.Lease
  alias Dawarich.Points.AnomalyBackfillProgress, as: Progress

  def run(repo, %{"user_id" => user_id} = args, opts \\ []) do
    if repo.query!("SELECT id FROM users WHERE id=$1 AND deleted_at IS NULL", [user_id],
         log: false
       ).rows == [],
       do:
         raise(Dawarich.Digests.Context.UserNotFound,
           message:
             "Couldn't find User with 'id'=#{user_id} [WHERE \"users\".\"deleted_at\" IS NULL]"
         )

    name = "anomaly_backfill:#{user_id}"

    Lease.with_lease(
      repo,
      name,
      fn holder ->
        fence = fn -> fence!(repo, name, holder) end
        progress = Progress.load(repo, args)
        unless Progress.reset?(progress), do: reset!(repo, args, fence)
        unless Progress.filtered?(progress), do: filter!(repo, args, progress, opts, fence)

        {:ok, :ok} =
          repo.transaction(fn ->
            fence.()
            Progress.clear!(repo, args)
          end)

        true
      end,
      Keyword.get(opts, :lease, [])
    )
    |> case do
      {:error, :timeout} -> {:error, :busy}
      result -> result
    end
  end

  defp reset!(repo, args, fence) do
    {:ok, :ok} =
      repo.transaction(fn ->
        fence.()

        if args["reset"] do
          cleared =
            repo.query!(
              "UPDATE points SET anomaly=false,updated_at=NOW() WHERE user_id=$1 AND anomaly IS TRUE",
              [args["user_id"]],
              log: false
            ).num_rows

          if cleared > 0,
            do:
              RailsCommands.insert!(repo, "points.tile_epoch", %{
                "user_id" => args["user_id"],
                "timestamps" => []
              })
        end

        Progress.reset!(repo, args)
        fence.()
      end)

    :ok
  end

  defp filter!(repo, args, progress, opts, fence) do
    months =
      repo.query!(
        "SELECT DISTINCT extract(epoch FROM date_trunc('month',to_timestamp(timestamp)))::bigint FROM points WHERE user_id=$1 ORDER BY 1",
        [args["user_id"]],
        log: false
      ).rows

    for [first] <- months, first > Progress.cursor(progress) do
      [[last]] =
        repo.query!(
          "SELECT extract(epoch FROM (to_timestamp($1) + interval '1 month'))::bigint",
          [first],
          log: false
        ).rows

      if fun = opts[:before_month], do: fun.(first, last)

      {:ok, :ok} =
        repo.transaction(fn ->
          fence.()

          AnomalyFilter.call(repo, args["user_id"], first, last,
            zone: args["ambient_zone"],
            invalidate_dependents: !args["reset"],
            job_queue: "low_priority",
            fence: fn fun ->
              fence.()
              result = fun.()
              fence.()
              result
            end
          )

          Progress.month!(repo, args, first)
          fence.()
        end)

      if fun = opts[:after_month], do: fun.(first)
    end

    :ok
  end

  defp fence!(repo, name, holder) do
    case repo.query!(
           "SELECT holder,expires_at>statement_timestamp() FROM phoenix.leases WHERE name=$1 FOR UPDATE",
           [name],
           log: false
         ).rows do
      [[^holder, true]] -> :ok
      _ -> raise "anomaly backfill lease lost"
    end
  end
end
