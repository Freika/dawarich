defmodule Dawarich.Jobs.TestEchoWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :default,
    unique: [keys: [:n], states: [:available, :scheduled, :retryable], period: :infinity]

  def args_from_command(1, %{"n" => n}) when is_integer(n), do: {:ok, %{"n" => n}}
  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(_job), do: :ok
end
