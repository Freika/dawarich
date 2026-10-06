defmodule Dawarich.Jobs.HealthTest do
  use ExUnit.Case, async: false

  alias Dawarich.Jobs.Health

  setup do
    Health.reset()
    on_exit(&Health.reset/0)
  end

  test "health cache returns the value at exactly sixty seconds and unknown just after" do
    unknown = %{"status" => "unknown", "alarm" => false}
    value = %{"status" => "ok", "alarm" => true}
    assert Health.summary() == unknown
    assert Health.refresh(compute: fn -> value end, clock: fn -> 100 end) == value
    assert Health.summary(fn -> 160 end) == value
    assert Health.summary(fn -> 160.000001 end) == unknown
  end

  test "health cache reads never query SQL" do
    value = %{"status" => "absent", "alarm" => false}
    Health.refresh(compute: fn -> value end)
    parent = self()
    id = {__MODULE__, make_ref()}
    :telemetry.attach_many(id, [[:dawarich, :repo, :query], [:dawarich, :scratch_repo, :query]], fn _, _, _, _ -> send(parent, :sql) end, nil)
    on_exit(fn -> :telemetry.detach(id) end)
    assert Health.summary() == value
    refute_received :sql
  end
  test "health refresher survives a failed refresh without replacing the last value" do
    value = %{"status" => "ok", "alarm" => false}
    Health.refresh(compute: fn -> value end)
    parent = self()
    refresh = fn ->
      send(parent, :attempted)
      raise "synthetic-private-refresher-payload"
    end

    log = ExUnit.CaptureLog.capture_log(fn ->
      pid = start_supervised!({Dawarich.Jobs.HealthRefresher, refresh: refresh})
      send(pid, :refresh)
      :sys.get_state(pid)
      assert Process.alive?(pid)
      assert Health.summary() == value
      assert_receive :attempted
    end)
    refute log =~ "synthetic-private-refresher-payload"
  end

  test "jobs supervisor starts the health refresher child" do
    oban = Dawarich.HealthTestOban
    start_supervised!({Oban, name: oban, repo: Dawarich.ScratchRepo, prefix: "oban", testing: :manual})
    jobs = start_supervised!({Dawarich.Jobs.Supervisor, node: "health-test", repo: Dawarich.ScratchRepo, public_repo: Dawarich.ScratchRepo, oban: oban, entries: [], auto: false})
    {:workers, workers, :supervisor, _} = List.keyfind(Supervisor.which_children(jobs), :workers, 0)
    assert {Dawarich.Jobs.HealthRefresher, pid, :worker, _} = List.keyfind(Supervisor.which_children(workers), Dawarich.Jobs.HealthRefresher, 0)
    assert Process.alive?(pid)
  end

end
