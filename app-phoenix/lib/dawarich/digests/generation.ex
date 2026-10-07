defmodule Dawarich.Digests.Generation do
  @moduledoc false

  alias Dawarich.Digests.{Execution, Failure, Run}
  alias Dawarich.Jobs.Processed
  alias Dawarich.Mail.ResidualCommands
  alias Dawarich.Stats.EffectIdentity

  def receipt(kind, args) do
    args["execution_receipt"] ||
      EffectIdentity.id(args["event_id"], "digests.calculate_" <> period(kind), args)
  end

  def run(repo, kind, args, opts \\ []) do
    terminal = receipt(kind, args)

    if completed?(repo, kind, args, terminal) do
      :ok
    else
      callback(opts, :before_claim)

      case Dawarich.Transaction.run(repo, fn ->
             Execution.lock!(repo, kind, args, terminal)
             Execution.adopt!(repo, kind, args, terminal)

             case Execution.read(repo, kind, args) do
               {state, _} when state in ["generated", "published"] -> :ok
               _ -> generate!(repo, kind, args, terminal, opts)
             end
           end) do
        {:ok, {:failed, error}} -> {:error, error}
        {:ok, :ok} -> publish(repo, kind, args, terminal, opts)
        {:error, reason} -> {:error, reason}
      end
    end
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp completed?(repo, kind, args, terminal) do
    {:ok, result} =
      Dawarich.Transaction.run(repo, fn ->
        Execution.lock!(repo, kind, args, terminal)
        Execution.adopt!(repo, kind, args, terminal)
        match?({"published", _}, Execution.read(repo, kind, args))
      end)

    result
  end

  defp generate!(repo, kind, args, terminal, opts) do
    Execution.write!(repo, kind, args, "claimed")
    function = if period(kind) == "month", do: :monthly, else: :yearly

    case apply(Run, function, [repo, args, opts]) do
      {:error, error, stack} ->
        generation_failed(repo, kind, args, error, stack)

      {:error, error} ->
        generation_failed(repo, kind, args, error, [])

      {:ok, _} ->
        generated(repo, kind, args, terminal, "mail")

      :missing ->
        generated(repo, kind, args, terminal, "missing")
    end
  end

  defp generation_failed(repo, kind, args, error, stack) do
    Execution.release!(repo, kind, args)
    Failure.create!(repo, kind, args["user_id"], error, stack)
    {:failed, error}
  end

  defp generated(repo, kind, args, terminal, outcome) do
    Execution.write!(repo, kind, args, "generated", outcome)
    Execution.mirror!(repo, kind, args, terminal, outcome)
    :ok
  end

  defp publish(repo, kind, args, terminal, opts) do
    case Dawarich.Transaction.run(repo, fn ->
           Execution.lock!(repo, kind, args, terminal)

           case Execution.read(repo, kind, args) do
             {"generated", outcome} ->
               if outcome == "mail",
                 do:
                   ResidualCommands.digest(
                     repo,
                     period(kind),
                     Map.put(args, "event_id", terminal)
                   )

               Execution.write!(repo, kind, args, "published", outcome)
               Processed.mark!(repo, terminal, "digests.calculate_" <> period(kind))
               callback(opts, :after_terminal)
               :ok

             {"published", _} ->
               :ok
           end
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp period(kind), do: if(kind in [:monthly, "monthly"], do: "month", else: "year")
  defp callback(opts, key), do: if(fun = Keyword.get(opts, key), do: fun.())
end
