defmodule Dawarich.Digests.Generation do
  @moduledoc false

  alias Dawarich.Digests.{Failure, Run}
  alias Dawarich.Jobs.Processed
  alias Dawarich.Mail.ResidualCommands
  alias Dawarich.Stats.EffectIdentity

  def receipt(kind, args) do
    args["execution_receipt"] ||
      EffectIdentity.id(args["event_id"], "digests.calculate_" <> period(kind), args)
  end

  def run(repo, kind, args, opts \\ []) do
    terminal_id = receipt(kind, args)
    release_failed!(repo, kind, args, terminal_id)

    if Processed.done?(repo, terminal_id) or legacy_done?(repo, kind, args) do
      :ok
    else
      callback(opts, :before_claim)

      case generate(repo, kind, args, terminal_id, opts) do
        {:ok, {:failed, error}} ->
          {:error, error}

        {:ok, result} ->
          settle(repo, kind, args, terminal_id, result, opts)

        {:error, reason} ->
          {:error, reason}
      end
    end
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp release_failed!(repo, kind, args, terminal_id) do
    handler = "digests.generate_" <> period(kind)
    checkpoint = EffectIdentity.id(args["event_id"], handler, args)

    {:ok, :ok} =
      Dawarich.Transaction.run(repo, fn ->
        deleted =
          repo.query!(
            "DELETE FROM phoenix.processed_commands WHERE event_id=$1 AND handler=$2 RETURNING event_id",
            [Ecto.UUID.dump!(checkpoint), handler <> ":failed"],
            log: false
          )

        if deleted.num_rows == 1 do
          repo.query!(
            "DELETE FROM phoenix.processed_commands WHERE event_id=$1 AND handler=$2",
            [Ecto.UUID.dump!(terminal_id), "digests.calculate_" <> period(kind)],
            log: false
          )
        end

        :ok
      end)
  end

  defp generate(repo, kind, args, terminal_id, opts) do
    handler = "digests.generate_" <> period(kind)
    checkpoint = EffectIdentity.id(args["event_id"], handler, args)
    shared = EffectIdentity.id(terminal_id, handler, %{})

    Dawarich.Transaction.run(repo, fn ->
      repo.query!(
        "SELECT pg_advisory_xact_lock(hashtextextended($1,0))",
        [terminal_id],
        log: false
      )

      cond do
        Processed.done?(repo, terminal_id) or legacy_done?(repo, kind, args) ->
          "complete"

        Processed.done?(repo, shared) ->
          outcome(repo, shared, handler)

        true ->
          state = generate_claim(repo, kind, args, opts, checkpoint, handler)

          unless match?({:failed, _}, state),
            do: Processed.mark!(repo, shared, handler <> ":" <> state)

          state
      end
    end)
  end

  defp generate_claim(repo, kind, args, opts, checkpoint, handler) do
    if Processed.claim!(repo, checkpoint, handler) do
      function = if period(kind) == "month", do: :monthly, else: :yearly
      result = apply(Run, function, [repo, args, opts])

      state =
        case result do
          {:ok, _id} ->
            "mail"

          :missing ->
            "missing"

          {:error, error, stack} ->
            Failure.create!(repo, kind, args["user_id"], error, stack)
            {:failed, error}
        end

      case state do
        {:failed, _} ->
          repo.query!(
            "DELETE FROM phoenix.processed_commands WHERE event_id=$1",
            [Ecto.UUID.dump!(checkpoint)],
            log: false
          )

        _ ->
          repo.query!(
            "UPDATE phoenix.processed_commands SET handler=$2 WHERE event_id=$1",
            [Ecto.UUID.dump!(checkpoint), handler <> ":" <> state],
            log: false
          )
      end

      state
    else
      outcome(repo, checkpoint, handler)
    end
  end

  defp outcome(repo, checkpoint, handler) do
    [[saved]] =
      repo.query!(
        "SELECT handler FROM phoenix.processed_commands WHERE event_id=$1",
        [Ecto.UUID.dump!(checkpoint)],
        log: false
      ).rows

    String.replace_prefix(saved, handler <> ":", "")
  end

  defp legacy_done?(repo, kind, args) do
    repo.query!(
      "SELECT 1 FROM phoenix.processed_commands WHERE event_id=$1 AND handler=$2",
      [Ecto.UUID.dump!(args["event_id"]), "digests.calculate_" <> period(kind)],
      log: false
    ).num_rows == 1
  end

  defp settle(repo, kind, args, terminal_id, result, opts) do
    Processed.once(repo, terminal_id, "digests.calculate_" <> period(kind), fn ->
      if result == "mail",
        do: ResidualCommands.digest(repo, period(kind), Map.put(args, "event_id", terminal_id))

      callback(opts, :after_terminal)
      :ok
    end)
  end

  defp period(kind), do: if(kind in [:monthly, "monthly"], do: "month", else: "year")

  defp callback(opts, key) do
    if fun = Keyword.get(opts, key), do: fun.()
  end
end
