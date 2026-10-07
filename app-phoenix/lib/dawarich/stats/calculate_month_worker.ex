defmodule Dawarich.Stats.CalculateMonthWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3

  alias Dawarich.Stats.{CalculateMonth, EffectIdentity}
  alias Dawarich.Jobs.Processed

  def args_from_command(1, %{"execution_receipt" => receipt} = payload) do
    with {:ok, ^receipt} <- Ecto.UUID.cast(receipt),
         {:ok, args} <- args_from_command(1, Map.delete(payload, "execution_receipt")) do
      {:ok, Map.put(args, "execution_receipt", receipt)}
    else
      _ -> {:error, "invalid_payload"}
    end
  end

  def args_from_command(
        1,
        %{"user_id" => id, "year" => year, "month" => month, "notify_on_failure" => notify} =
          payload
      )
      when is_integer(id) and is_integer(year) and is_integer(month) and is_boolean(notify) and
             map_size(payload) == 4,
      do:
        {:ok, %{"user_id" => id, "year" => year, "month" => month, "notify_on_failure" => notify}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(job), do: perform(job, [])

  def perform(
        %Oban.Job{
          args:
            %{"user_id" => id, "year" => year, "month" => month, "notify_on_failure" => notify} =
              args
        } = job,
        opts
      ) do
    repo = Dawarich.Jobs.repo()
    source = args["event_id"] || "oban:#{job.id || Jason.encode!(args)}"

    receipt =
      args["execution_receipt"] || EffectIdentity.id(source, "stats.calculate_month", args)

    case Dawarich.Transaction.run(repo, fn ->
           if Processed.claim!(repo, receipt, "stats.calculate_month") do
             case CalculateMonth.call(repo, id, year, month, Keyword.put(opts, :notify, notify)) do
               result when result in [:ok, :missing] ->
                 :ok

               {:error, reason} ->
                 repo.query!(
                   "DELETE FROM phoenix.processed_commands WHERE event_id=$1",
                   [Ecto.UUID.dump!(receipt)],
                   log: false
                 )

                 {:error, reason}
             end
           else
             :ok
           end
         end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
