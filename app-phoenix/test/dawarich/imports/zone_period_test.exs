defmodule Dawarich.Imports.ZonePeriodTest do
  use ExUnit.Case, async: false
  alias Dawarich.Imports.ZonePeriod

  test "an import reads each time zone once and releases cached data after failure" do
    Code.ensure_loaded!(ZonePeriod)
    function = {ZonePeriod, :read!, 1}
    :erlang.trace_pattern(function, true, [:call_count])
    on_exit(fn -> :erlang.trace_pattern(function, false, [:call_count]) end)

    assert_raise RuntimeError, "abort import", fn ->
      ZonePeriod.with_cache(fn ->
        first = ZonePeriod.load!("Europe/Berlin")
        assert ZonePeriod.load!("Europe/Berlin") == first
        assert ZonePeriod.load!("Etc/UTC") != first
        assert {:call_count, 2} = :erlang.trace_info(function, :call_count)
        raise "abort import"
      end)
    end

    assert Process.get({ZonePeriod, :cache}) == nil

    ZonePeriod.with_cache(fn ->
      ZonePeriod.load!("Europe/Berlin")
      assert {:call_count, 3} = :erlang.trace_info(function, :call_count)
    end)

    assert Process.get({ZonePeriod, :cache}) == nil
  end

  test "nested caches restore the parent and remain isolated across processes" do
    key = {ZonePeriod, :cache}

    ZonePeriod.with_cache(fn ->
      ZonePeriod.load!("Europe/Berlin")
      parent = Process.get(key)

      ZonePeriod.with_cache(fn ->
        assert Process.get(key) == %{}
        ZonePeriod.load!("Etc/UTC")
      end)

      assert Process.get(key) == parent

      assert_raise RuntimeError, "nested failure", fn ->
        ZonePeriod.with_cache(fn -> raise "nested failure" end)
      end

      assert Process.get(key) == parent

      assert Task.async(fn ->
               assert Process.get(key) == nil
               ZonePeriod.with_cache(fn -> ZonePeriod.load!("Etc/UTC") end)
               Process.get(key)
             end)
             |> Task.await() == nil

      assert Process.get(key) == parent
    end)

    assert Process.get(key) == nil
  end
end
