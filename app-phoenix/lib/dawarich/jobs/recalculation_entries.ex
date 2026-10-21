defmodule Dawarich.Jobs.RecalculationEntries do
  @moduledoc false

  def entries do
    Enum.map(
      [
        {"transportation.user_reclassify", Dawarich.Transportation.UserReclassifyWorker},
        {"stats.full_recalculation", Dawarich.Stats.FullRecalculationWorker},
        {"users.recalculate_data", Dawarich.Users.RecalculateWorker},
        {"visits.user_redetect", Dawarich.Visits.UserRedetectWorker},
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
