defmodule Dawarich.Digests.Generation do
  @moduledoc false

  alias Dawarich.Digests.{Failure, Run}
  alias Dawarich.Jobs.Processed
  alias Dawarich.RailsCommands

  def run(repo, kind, args, opts \\ []) do
    event_id = Map.fetch!(args, "event_id")

    if Processed.done?(repo, event_id) do
      :ok
    else
      function = if kind in [:monthly, "monthly"], do: :monthly, else: :yearly
      result = apply(Run, function, [repo, args, opts])
      settle(repo, kind, args, result, opts)
    end
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp settle(repo, kind, args, result, opts) do
    period = if kind in [:monthly, "monthly"], do: "month", else: "year"

    repo.transaction(fn ->
      callback(opts, :before_claim)

      if Processed.claim!(repo, args["event_id"], "digests.calculate_" <> period) do
        terminal(repo, kind, period, args, result)
        callback(opts, :after_terminal)
      end

      :ok
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp terminal(repo, _kind, period, args, {:ok, _id}) do
    fields =
      if period == "month", do: ~w(user_id year month time_zone), else: ~w(user_id year time_zone)

    RailsCommands.insert!(repo, "digests.email_" <> period, Map.take(args, fields))
  end

  defp terminal(repo, kind, _period, args, {:error, error, stack}),
    do: Failure.create!(repo, kind, args["user_id"], error, stack)

  defp terminal(_repo, _kind, _period, _args, :missing), do: :ok

  defp callback(opts, key) do
    if fun = Keyword.get(opts, key), do: fun.()
  end
end
