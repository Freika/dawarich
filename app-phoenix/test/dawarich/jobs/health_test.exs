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
end
