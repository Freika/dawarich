defmodule Dawarich.RawData.ContentionTest do
  use ExUnit.Case, async: true

  alias Dawarich.RawData.Contention

  defp error(code),
    do: %Postgrex.Error{
      postgres: %{code: code, severity: "ERROR", pg_code: "XX000", message: "x"}
    }

  test "retries a contention error three times, then raises; other errors raise at once" do
    counter = :counters.new(1, [])
    opts = [sleep: fn _ -> :ok end]

    assert_raise Postgrex.Error, fn ->
      Contention.retry(opts, fn ->
        :counters.add(counter, 1, 1) && raise(error(:deadlock_detected))
      end)
    end

    assert :counters.get(counter, 1) == 4

    other = :counters.new(1, [])

    assert_raise Postgrex.Error, fn ->
      Contention.retry(opts, fn ->
        :counters.add(other, 1, 1) && raise(error(:unique_violation))
      end)
    end

    assert :counters.get(other, 1) == 1
  end
end
