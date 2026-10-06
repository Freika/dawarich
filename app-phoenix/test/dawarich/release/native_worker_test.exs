defmodule Dawarich.NativeWorkerTest do
  use ExUnit.Case, async: true

  alias Dawarich.NativeWorker

  test "stage barrier identifies the worker before continuation" do
    parent = self()
    send(self(), {:native_stage, self(), :unrelated})

    worker =
      {pid, _} =
      NativeWorker.start(fn ->
        send(parent, {:native_stage, self(), :writing})
        receive do: (:continue -> :ok)
      end)

    assert NativeWorker.stage(worker) == {:ok, :writing}
    send(pid, :continue)
    assert NativeWorker.complete(worker) == {:ok, :ok}
  end

  test "stage barrier reports worker exit before readiness" do
    worker = NativeWorker.start(fn -> exit(:before_writing) end)
    assert NativeWorker.stage(worker) == {:error, :before_writing}
  end

  test "completion reports the actual result and normal exit" do
    worker = NativeWorker.start(fn -> :migrated end)
    assert NativeWorker.complete(worker) == {:ok, :migrated}
  end

  test "completion rejects abnormal exit after a result" do
    parent = self()

    worker =
      spawn_monitor(fn ->
        send(parent, {:native_result, self(), :migrated})
        exit(:after_result)
      end)

    assert NativeWorker.complete(worker) == {:error, :after_result}
  end

  test "completion reports a crash instead of successful migration" do
    worker = NativeWorker.start(fn -> exit(:write_failed) end)
    assert NativeWorker.complete(worker) == {:error, :write_failed}
  end
end
