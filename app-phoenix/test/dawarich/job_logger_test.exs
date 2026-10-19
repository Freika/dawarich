defmodule Dawarich.JobLoggerTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  setup do
    level = Logger.level()
    Logger.configure(level: :info)
    :ok = Dawarich.JobLogger.attach()

    on_exit(fn ->
      Dawarich.JobLogger.detach()
      Logger.configure(level: level)
    end)
  end

  test "job lines carry worker, queue and duration but never the args" do
    job = %Oban.Job{
      id: 7,
      worker: "Dawarich.SyntheticWorker",
      queue: "tracks",
      attempt: 1,
      max_attempts: 3,
      args: %{"track" => %{"path" => "LINESTRING(13.4050 52.5200,13.4060 52.5210)"}},
      meta: %{},
      tags: []
    }

    meta = %{job: job, conf: %{name: Oban}}

    log =
      capture_log([level: :info], fn ->
        :telemetry.execute([:oban, :job, :start], %{system_time: 1}, meta)

        :telemetry.execute(
          [:oban, :job, :stop],
          %{duration: 1_000_000, queue_time: 10},
          Map.put(meta, :state, :success)
        )

        :telemetry.execute(
          [:oban, :job, :exception],
          %{duration: 1, queue_time: 1},
          Map.merge(meta, %{
            state: :failure,
            kind: :error,
            reason: %RuntimeError{message: "synthetic failure"},
            stacktrace: []
          })
        )
      end)

    assert log =~ "Dawarich.SyntheticWorker"
    assert log =~ "job:start"
    assert log =~ "job:stop"
    assert log =~ "synthetic failure"
    assert log =~ "tracks"
    refute log =~ "LINESTRING"
    refute log =~ "13.405"
  end
end
