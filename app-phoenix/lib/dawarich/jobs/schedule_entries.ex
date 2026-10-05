defmodule Dawarich.Jobs.ScheduleEntries do
  @moduledoc false

  def entries do
    [
      %{
        key: "cron:nightly_reverse_geocoding_job",
        kind: :cron,
        expression: "15 1 * * *",
        worker: Dawarich.Geocoding.NightlyWorker,
        claimable: false,
        catch_up: false
      },
      %{
        key: "cron:visit_suggesting_job",
        kind: :cron,
        expression: "5 0 * * *",
        worker: Dawarich.Visits.BulkSweepWorker,
        claimable: false,
        catch_up: false
      },
      %{
        key: "command:visits.bulk_suggest",
        kind: :command,
        worker: Dawarich.Visits.BulkSweepWorker,
        claimable: false
      }
    ]
  end
end
