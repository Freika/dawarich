defmodule Dawarich.ImportLeaseFixture do
  @moduledoc false
  import Dawarich.JobsCase, only: [rows: 1, rows: 2]

  def create do
    [[user], [other]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES ('lease@example.test',now(),now()),('other-lease@example.test',now(),now()) RETURNING id"
      )

    [[id]] =
      rows(
        "INSERT INTO imports(user_id,name,source,created_at,updated_at) VALUES ($1,'lease.gpx',4,now(),now()) RETURNING id",
        [user]
      )

    event = Ecto.UUID.generate()

    args = %{
      "event_id" => event,
      "import_id" => id,
      "user_id" => user,
      "time_zone" => "Europe/Berlin"
    }

    [[job_id]] =
      rows(
        "INSERT INTO oban.oban_jobs(state,queue,worker,args,attempt,max_attempts,attempted_at) VALUES ('executing','imports','Dawarich.Imports.ProcessGpxWorker',$1,1,3,now()) RETURNING id",
        [args]
      )

    Dawarich.Jobs.Ownership.put!(Dawarich.ScratchRepo, "command:imports.process_gpx", :oban)

    %{
      import: %{id: id, user_id: user},
      job: %Oban.Job{id: job_id, attempt: 1, args: args},
      other: other
    }
  end
end
