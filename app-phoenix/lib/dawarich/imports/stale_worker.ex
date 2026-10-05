defmodule Dawarich.Imports.StaleWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :exports,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: Dawarich.Imports.StaleRecovery.run(Dawarich.Jobs.repo())
end
