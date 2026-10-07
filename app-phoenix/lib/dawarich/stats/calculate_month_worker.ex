defmodule Dawarich.Stats.CalculateMonthWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3

  alias Dawarich.Stats.CalculateMonth

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
  def perform(%Oban.Job{
        args: %{"user_id" => id, "year" => year, "month" => month, "notify_on_failure" => notify}
      }) do
    case CalculateMonth.call(Dawarich.Jobs.repo(), id, year, month, notify: notify) do
      :missing -> :ok
      result -> result
    end
  end
end
