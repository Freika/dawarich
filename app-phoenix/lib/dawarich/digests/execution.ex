defmodule Dawarich.Digests.Execution do
  @moduledoc false

  alias Dawarich.Jobs.Processed
  alias Dawarich.Stats.EffectIdentity

  def key(kind, args) do
    period = if kind in [:monthly, "monthly"], do: "month", else: "year"
    ["digests.calculate_" <> period, args["user_id"], args["year"], args["month"] || 0]
  end

  def lock!(repo, kind, args, receipt) do
    repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", [receipt], log: false)

    repo.query!(
      "SELECT pg_advisory_xact_lock(hashtextextended($1,0))",
      [Jason.encode!(key(kind, args))],
      log: false
    )
  end

  def read(repo, kind, args) do
    case repo.query!(
           "SELECT state,outcome,legacy FROM phoenix.digest_executions WHERE effect=$1 AND user_id=$2 AND year=$3 AND month=$4",
           key(kind, args),
           log: false
         ).rows do
      [[state, outcome, _legacy]] -> {state, outcome}
      [] -> nil
    end
  end

  def write!(repo, kind, args, state, outcome \\ nil) do
    repo.query!(
      "INSERT INTO phoenix.digest_executions(effect,user_id,year,month,state,outcome) VALUES($1,$2,$3,$4,$5,$6) " <>
        "ON CONFLICT(effect,user_id,year,month) DO UPDATE SET state=EXCLUDED.state,outcome=EXCLUDED.outcome,updated_at=now()",
      key(kind, args) ++ [state, outcome],
      log: false
    )

    :ok
  end

  def release!(repo, kind, args) do
    repo.query!(
      "DELETE FROM phoenix.digest_executions WHERE effect=$1 AND user_id=$2 AND year=$3 AND month=$4 AND state='claimed'",
      key(kind, args),
      log: false
    )
  end

  def adopt!(repo, kind, args, receipt) do
    legacy =
      repo.query!(
        "SELECT legacy FROM phoenix.digest_executions WHERE effect=$1 AND user_id=$2 AND year=$3 AND month=$4",
        key(kind, args),
        log: false
      ).rows

    if legacy in [[], [[true]]] do
      unless match?({"published", _}, read(repo, kind, args)) do
        [handler | _] = key(kind, args)
        generation = String.replace(handler, "calculate_", "generate_")
        old = EffectIdentity.id(args["event_id"], generation, args)
        shared = EffectIdentity.id(receipt, generation, %{})
        failed = marker(repo, old) == generation <> ":failed"

        if failed do
          repo.query!(
            "DELETE FROM phoenix.processed_commands WHERE event_id=$1 AND handler=$2",
            [Ecto.UUID.dump!(old), generation <> ":failed"],
            log: false
          )

          repo.query!(
            "DELETE FROM phoenix.processed_commands WHERE event_id=$1 AND handler=$2",
            [Ecto.UUID.dump!(receipt), handler],
            log: false
          )
        end

        cond do
          not failed and
              (marker(repo, receipt) == handler or marker(repo, args["event_id"]) == handler) ->
            write!(repo, kind, args, "published", "mail")

          marker(repo, shared) in [generation <> ":mail", generation <> ":missing"] ->
            write!(repo, kind, args, "generated", outcome(repo, shared, generation))

          marker(repo, old) in [generation <> ":mail", generation <> ":missing"] ->
            write!(repo, kind, args, "generated", outcome(repo, old, generation))

          true ->
            :ok
        end
      end

      repo.query!(
        "UPDATE phoenix.digest_executions SET legacy=false WHERE effect=$1 AND user_id=$2 AND year=$3 AND month=$4",
        key(kind, args),
        log: false
      )
    end
  end

  def mirror!(repo, kind, args, receipt, outcome) do
    [handler | _] = key(kind, args)
    generation = String.replace(handler, "calculate_", "generate_")

    Processed.mark!(
      repo,
      EffectIdentity.id(args["event_id"], generation, args),
      generation <> ":" <> outcome
    )

    Processed.mark!(
      repo,
      EffectIdentity.id(receipt, generation, %{}),
      generation <> ":" <> outcome
    )
  end

  defp marker(_repo, nil), do: nil

  defp marker(repo, id) do
    case repo.query!(
           "SELECT handler FROM phoenix.processed_commands WHERE event_id=$1",
           [Ecto.UUID.dump!(id)],
           log: false
         ).rows do
      [[handler]] -> handler
      [] -> nil
    end
  end

  defp outcome(repo, id, handler), do: String.replace_prefix(marker(repo, id), handler <> ":", "")
end
