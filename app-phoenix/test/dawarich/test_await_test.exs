defmodule Dawarich.TestAwaitTest do
  use ExUnit.Case, async: true

  import Dawarich.Test.Await

  test "await_receive waits for a sender whose work outlasts assert_receive's default window" do
    parent = self()

    spawn(fn ->
      Process.sleep(300)
      send(parent, {:done, self()})
    end)

    await_receive({:done, pid})
    assert is_pid(pid)
  end
end
