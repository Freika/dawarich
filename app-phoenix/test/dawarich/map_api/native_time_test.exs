defmodule Dawarich.MapApi.NativeTimeTest do
  use ExUnit.Case, async: true
  alias Dawarich.MapApi.NativeTime

  test "native time retains fractional precision and legacy HTTP date centuries" do
    now = ~U[2026-10-05 12:00:00Z]
    assert NativeTime.parse("2025-01-01T00:05:00.5Z", "UTC", now) == 1_735_689_900.5
    assert NativeTime.parse("not-a-date", "UTC", now) == nil

    assert NativeTime.http([{"if-modified-since", "Sunday, 06-Nov-94 08:49:37 GMT"}]) ==
             {:ok, ~N[1994-11-06 08:49:37]}

    assert NativeTime.http([{"if-modified-since", "Wed, 01 Jan 2025 00:05:00 GMT"}]) ==
             {:ok, ~N[2025-01-01 00:05:00]}
  end
end
