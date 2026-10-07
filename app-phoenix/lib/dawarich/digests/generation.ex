defmodule Dawarich.Digests.Generation do
  @moduledoc false

  alias Dawarich.Digests.{Failure, Run}
  alias Dawarich.Jobs.Processed
  alias Dawarich.Mail.ResidualCommands
  alias Dawarich.Stats.EffectIdentity

  def receipt(kind, args) do
    EffectIdentity.id(args["event_id"], "digests.calculate_" <> period(kind), args)
  end

  def run(repo, kind, args, opts \\ []) do
    terminal_id = receipt(kind, args)

    if Processed.done?(repo, terminal_id) do
      :ok
    else
      callback(opts, :before_claim)
      result = generate(repo, kind, args, opts)
      settle(repo, kind, args, terminal_id, result, opts)
    end
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp generate(repo, kind, args, opts) do
    handler = "digests.generate_" <> period(kind)
    checkpoint = EffectIdentity.id(args["event_id"], handler, args)

    {:ok, result} =
      Dawarich.Transaction.run(repo, fn ->
        if Processed.claim!(repo, checkpoint, handler) do
          function = if period(kind) == "month", do: :monthly, else: :yearly
          result = apply(Run, function, [repo, args, opts])
          state = generated(repo, kind, args, result)

          repo.query!(
            "UPDATE phoenix.processed_commands SET handler=$2 WHERE event_id=$1",
            [Ecto.UUID.dump!(checkpoint), handler <> ":" <> state],
            log: false
          )

          state
        else
          [[saved]] =
            repo.query!(
              "SELECT handler FROM phoenix.processed_commands WHERE event_id=$1",
              [Ecto.UUID.dump!(checkpoint)],
              log: false
            ).rows

          String.replace_prefix(saved, handler <> ":", "")
        end
      end)

    result
  end

  defp generated(_repo, _kind, _args, {:ok, _id}), do: "mail"
  defp generated(_repo, _kind, _args, :missing), do: "missing"

  defp generated(repo, kind, args, {:error, error, stack}) do
    Failure.create!(repo, kind, args["user_id"], error, stack)
    "failed"
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
