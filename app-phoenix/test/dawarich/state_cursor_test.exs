defmodule Dawarich.StateCursorTest do
  use Dawarich.JobsCase

  alias Dawarich.State

  test "a cursor row holds a Redis-style string until it is overwritten or deleted" do
    assert State.cursor(ScratchRepo, "c:x") == nil
    assert State.put_cursor(ScratchRepo, "c:x", "41") == :ok
    assert State.cursor(ScratchRepo, "c:x") == "41"
    assert State.put_cursor(ScratchRepo, "c:x", "[7,-2147483648]") == :ok
    assert State.cursor(ScratchRepo, "c:x") == "[7,-2147483648]"
    assert State.delete_cursor(ScratchRepo, "c:x") == :ok
    assert State.cursor(ScratchRepo, "c:x") == nil
  end

  test "increment starts a missing cursor at 1 and adds 1 to an integer one, as Redis INCR does" do
    assert State.increment_cursor(ScratchRepo, "c:turn") == 1
    assert State.increment_cursor(ScratchRepo, "c:turn") == 2
    assert State.put_cursor(ScratchRepo, "c:turn", "41") == :ok
    assert State.increment_cursor(ScratchRepo, "c:turn") == 42
    assert State.cursor(ScratchRepo, "c:turn") == "42"
  end

  test "incrementing a cursor that holds no integer fails, as Redis INCR does" do
    assert State.put_cursor(ScratchRepo, "c:json", "[1,2]") == :ok
    assert_raise Postgrex.Error, fn -> State.increment_cursor(ScratchRepo, "c:json") end
  end
end
