defmodule Dawarich.Digests.JobEntries do
  @moduledoc false

  alias Dawarich.Digests.{
    MonthlyScheduleWorker,
    MonthlyWorker,
    YearlyScheduleWorker,
    YearlyWorker
  }

  def entries do
    [
      %{
        key: "command:digests.calculate_month",
        kind: :command,
        worker: MonthlyWorker,
        claimable: false
      },
      %{
        key: "command:digests.calculate_year",
        kind: :command,
        worker: YearlyWorker,
        claimable: false
      },
      %{
        key: "cron:monthly_digest_scheduling_job",
        kind: :cron,
        expression: "0 4 2 * *",
        worker: MonthlyScheduleWorker,
        catch_up: false,
        claimable: false
      },
      %{
        key: "cron:yearly_digest_scheduling_job",
        kind: :cron,
        expression: "0 6 2 1 *",
        worker: YearlyScheduleWorker,
        catch_up: false,
        claimable: false
      }
    ]
  end
end
