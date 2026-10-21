defmodule Dawarich.Mail.Digests.MonthlyWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 3
  alias Dawarich.Mail.Digests.Enqueue

  def args_from_command(version, payload), do: Enqueue.args("monthly", version, payload)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: Enqueue.run(Dawarich.Jobs.repo(), "monthly", args)
end
