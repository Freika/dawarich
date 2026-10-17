defmodule Dawarich.Test.AfterCommit do
  import ExUnit.Assertions

  def drain(repo) do
    jobs =
      repo.query!(
        "SELECT id,worker,args FROM oban.oban_jobs WHERE worker=ANY($1) AND state IN ('available','scheduled') ORDER BY id",
        [["Dawarich.AfterCommit.Worker", "Dawarich.Points.VisitMonthsWorker"]],
        log: false
      ).rows

    for [id, worker, args] <- jobs do
      result =
        case worker do
          "Dawarich.AfterCommit.Worker" -> Dawarich.AfterCommit.Worker.run(repo, args)
          "Dawarich.Points.VisitMonthsWorker" -> Dawarich.Points.VisitMonthsWorker.run(repo, args)
        end

      assert :ok = result

      repo.query!(
        "UPDATE oban.oban_jobs SET state='completed',completed_at=now() WHERE id=$1",
        [id],
        log: false
      )
    end

    :ok
  end
end
