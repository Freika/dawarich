defmodule Dawarich.Imports.EventsTest do
  use ExUnit.Case, async: true

  test "progress wakeups are scoped by user and carry no private row data" do
    id = System.unique_integer([:positive])
    :ok = Dawarich.Imports.Events.subscribe(id)
    :ok = Dawarich.Imports.Events.broadcast(id + 1)
    refute_receive :imports_changed, 10
    :ok = Dawarich.Imports.Events.broadcast(id)
    assert_receive :imports_changed
  end
end
