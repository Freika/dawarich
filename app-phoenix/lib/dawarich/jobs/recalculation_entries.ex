defmodule Dawarich.Jobs.RecalculationEntries do
  @moduledoc false

  def entries do
    Enum.map(
      [
        {"stats.full_recalculation", Dawarich.Stats.FullRecalculationWorker},
        {"users.recalculate_data", Dawarich.Users.RecalculateWorker},
        {"points.anomaly_backfill", Dawarich.Points.AnomalyBackfillWorker},
        {"release.anomalies", Dawarich.ReleaseOperations.Anomalies},
        {"release.anomalies_user", Dawarich.ReleaseOperations.AnomaliesUser},
        {"release.per_tracker", Dawarich.ReleaseOperations.PerTracker}
      ],
      fn {type, worker} ->
        %{key: "command:" <> type, kind: :command, worker: worker, claimable: false}
      end
    )
  end
end
