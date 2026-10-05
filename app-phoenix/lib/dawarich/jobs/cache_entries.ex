defmodule Dawarich.Jobs.CacheEntries do
  @moduledoc false

  def entries do
    [
      %{
        key: "command:cache.preheat_user",
        kind: :command,
        worker: Dawarich.Cache.PreheatUserWorker,
        claimable: false
      },
      %{
        key: "cron:cache_preheating_job",
        kind: :cron,
        worker: Dawarich.Cache.PreheatSweepWorker,
        expression: "0 0 * * *",
        catch_up: false,
        claimable: false
      }
    ]
  end
end
