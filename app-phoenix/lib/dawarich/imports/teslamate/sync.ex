defmodule Dawarich.Imports.Teslamate.Sync do
  @moduledoc false
  alias Dawarich.Imports.Teslamate.{Client, Point, State, Effects}
  alias Dawarich.Jobs.Processed
  alias Dawarich.State.Lease
  @key "command:imports.teslamate_sync"
  @empty %{"cars" => 0, "drives" => 0, "points" => 0, "skipped_points" => 0}

  def run(repo, args, opts \\ []) do
    if Processed.done?(repo, args["event_id"]) do
      {:ok, %{"skipped" => true}}
    else
      case Lease.with_lease(
             repo,
             "teslamate-sync:#{args["user_id"]}",
             fn holder -> begin(repo, args, holder, opts) end,
             timeout_ms: 0
           ) do
        {:ok, result} -> result
        {:error, :timeout} -> {:ok, %{"skipped" => true}}
      end
    end
  end

  defp begin(repo, args, holder, opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0) |> DateTime.truncate(:second)
    hosted = Keyword.get_lazy(opts, :self_hosted?, &Dawarich.ReleaseMigration.self_hosted?/0)

    result =
      repo.transaction(fn ->
        ctx =
          State.load!(repo, args["user_id"])
          |> Map.merge(%{
            holder: holder,
            hosted: hosted,
            now: now,
            event: args["event_id"],
            job: opts[:job]
          })

        State.fence!(ctx)
        url = ctx.settings["teslamate_url"]

        if Dawarich.Ingest.Ruby.blank?(url) or
             (opts[:worker] == true and not State.allowed?(ctx, now, hosted)) do
          :skip
        else
          State.update!(ctx, %{
            "teslamate_processing_pending" => true,
            "teslamate_processing_pending_url" => url
          })

          ctx
        end
      end)

    case result do
      {:ok, :skip} -> {:ok, %{"skipped" => true}}
      {:ok, ctx} -> sync(ctx)
      {:error, :lost} -> {:cancel, :ownership_lost}
    end
  end

  defp sync(ctx) do
    client =
      Client.new(
        ctx.settings["teslamate_url"],
        Enum.map([:username, :password, :api_token, :skip_ssl_verification], fn k ->
          {k, ctx.settings["teslamate_#{k}"]}
        end)
        |> Keyword.update!(:skip_ssl_verification, &Dawarich.MapApi.Params.boolean/1)
      )

    initial = %{
      counts: @empty,
      failures: [],
      range: nil,
      months: [],
      truncated: false,
      completed: false,
      fatal: nil
    }

    case Client.cars(client) do
      {:ok, cars} ->
        outcome =
          Enum.reduce_while(cars, initial, fn car, acc ->
            cond do
              acc[:cancel] == true or acc.fatal != nil ->
                {:halt, acc}

              quota?(ctx) ->
                {:halt, %{acc | truncated: true}}

              length(acc.failures) >= 3 ->
                {:halt, acc}

              true ->
                acc = update_in(acc.counts["cars"], &(&1 + 1))
                {:cont, car(ctx, client, car["car_id"], 1, acc)}
            end
          end)

        completed = length(outcome.failures) < 3 and is_nil(outcome.fatal)
        finish(ctx, %{outcome | completed: completed})

      {:error, message} ->
        finish(ctx, %{initial | fatal: message})
    end
  end

  defp car(ctx, client, id, page, acc) do
    case current?(ctx) do
      false ->
        Map.put(acc, :cancel, true)

      true ->
        case Client.drives(client, id,
               page: page,
               show: 100,
               start_date: start(ctx),
               end_date: ctx.now
             ) do
          {:error, message} ->
            %{acc | failures: acc.failures ++ ["car #{id}, page #{page}: #{message}"]}

          {:ok, result} ->
            acc =
              Enum.reduce_while(result.drives, acc, fn drive, a ->
                cond do
                  a[:cancel] == true or a.fatal != nil -> {:halt, a}
                  quota?(ctx) -> {:halt, %{a | truncated: true}}
                  length(a.failures) >= 3 -> {:halt, a}
                  true -> {:cont, drive(ctx, client, id, drive["drive_id"], result.units, a)}
                end
              end)

            cond do
              acc[:cancel] == true or acc.fatal != nil or length(acc.failures) >= 3 -> acc
              quota?(ctx) -> %{acc | truncated: acc.truncated or length(result.drives) == 100}
              length(result.drives) < 100 -> acc
              true -> car(ctx, client, id, page + 1, acc)
            end
        end
    end
  end

  defp drive(ctx, client, car, id, units, acc) do
    with {:ok, result} <- Client.drive(client, car, id),
         {:ok, payloads, skipped} <- Point.prepare_drive(result, car, id, units) do
      case ctx.repo.transaction(fn ->
             {selected, truncated} = State.limit(ctx, payloads)

             rows =
               selected
               |> Enum.sort_by(& &1.timestamp)
               |> Dawarich.Ingest.Intake.prepare(ctx.id)
               |> Dawarich.Ingest.Intake.write(ctx.id, repo: ctx.repo, mode: :bulk)

             {rows, length(selected), skipped + length(payloads) - length(selected), truncated}
           end) do
        {:ok, {rows, count, skipped, truncated}} ->
          counts =
            acc.counts
            |> Map.update!("drives", &(&1 + 1))
            |> Map.update!("points", &(&1 + count))
            |> Map.update!("skipped_points", &(&1 + skipped))

          Effects.record(
            ctx,
            %{acc | counts: counts, truncated: acc.truncated or truncated},
            rows
          )

        {:error, :lost} ->
          Map.put(acc, :cancel, true)
      end
    else
      {:error, message} ->
        %{acc | failures: acc.failures ++ ["car #{car}, drive #{id}: #{message}"]}
    end
  rescue
    error -> %{acc | fatal: Exception.message(error)}
  end

  defp finish(ctx, acc) do
    result =
      ctx.repo.transaction(fn ->
        State.fence!(ctx)
        Effects.finalize(ctx, acc)

        if acc.completed,
          do:
            State.update!(ctx, %{
              "teslamate_processing_pending" => false,
              "teslamate_processing_pending_url" => nil
            })

        if acc.completed and acc.failures == [] and not acc.truncated do
          State.update!(ctx, %{
            "teslamate_last_synced_at" => DateTime.to_iso8601(ctx.now),
            "teslamate_last_synced_url" => ctx.settings["teslamate_url"]
          })
        end

        if acc.completed and acc.failures == [], do: Processed.mark!(ctx.repo, ctx.event, @key)

        if ((acc.failures != [] or acc.fatal != nil) and ctx.job) &&
             ctx.job.attempt >= ctx.job.max_attempts do
          Effects.failure(ctx, message(acc))
        end
      end)

    cond do
      result == {:error, :lost} or acc[:cancel] ->
        {:cancel, :ownership_lost}

      acc.failures != [] or acc.fatal != nil ->
        {:error, message(acc)}

      true ->
        {:ok, acc.counts}
    end
  end

  defp message(%{fatal: message}) when is_binary(message), do: message
  defp message(acc), do: "TeslaMateApi sync incomplete: " <> Enum.join(acc.failures, "; ")

  defp current?(ctx), do: match?({:ok, _}, ctx.repo.transaction(fn -> State.fence!(ctx) end))
  defp quota?(%{hosted: true}), do: false

  defp quota?(ctx),
    do:
      ctx.repo.query!("SELECT points_count>=10000000 FROM users WHERE id=$1", [ctx.id],
        log: false
      ).rows == [[true]]

  defp start(ctx) do
    if ctx.settings["teslamate_last_synced_url"] == ctx.settings["teslamate_url"] do
      case DateTime.from_iso8601(ctx.settings["teslamate_last_synced_at"] || "") do
        {:ok, time, _} -> DateTime.add(time, -7 * 86400)
        _ -> nil
      end
    end
  end
end
