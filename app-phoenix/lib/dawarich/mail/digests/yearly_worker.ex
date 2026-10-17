defmodule Dawarich.Mail.Digests.YearlyWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 3
  alias Dawarich.Mail.Digests.Enqueue

  def args_from_command(version, payload), do: Enqueue.args("yearly", version, payload)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: Enqueue.run(Dawarich.Jobs.repo(), "yearly", args)
end
