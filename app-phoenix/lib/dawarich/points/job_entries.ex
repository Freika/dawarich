defmodule Dawarich.Points.JobEntries do
  @moduledoc false

  def entries do
    Enum.map(
      [
        {"points.tile_epoch", Dawarich.Points.TileEpochWorker},
        {"points.live_broadcast", Dawarich.Points.LiveBroadcastWorker},
        {"points.anomaly_filter", Dawarich.Points.AnomalyArrivalWorker}
      ],
      fn {type, worker} ->
        %{key: "command:" <> type, kind: :command, worker: worker, claimable: false}
      end
    )
  end
end
