defmodule Dawarich.Points.ImportCardWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, %{"user_id" => user, "import_id" => import}) do
    if repo.query!("SELECT id FROM imports WHERE id=$1 AND user_id=$2", [import, user],
         log: false
       ).num_rows == 1,
       do: Dawarich.Imports.Events.broadcast(user)

    :ok
  end
end
