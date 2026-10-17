defmodule Dawarich.Families.ClockTest do
  use Dawarich.IngestCase, async: true
  alias Dawarich.Families.Clock

  test "sharing dates accept Rails date-only offsetless space and nanosecond forms in the actor zone" do
    Dawarich.RailsTime.with_zone("Europe/Berlin", fn ->
      for value <- ["2099-01-01", "2099-01-01T00:00", "2099-01-01 00:00:00"] do
        assert Clock.parse(value) == ~N[2098-12-31 23:00:00.000000]
      end

      assert Clock.parse("2099-01-01T00:00:00.1234567Z") == ~N[2099-01-01 00:00:00.123456]
      assert Clock.parse("2099-01-01 00:00:00Z") == ~N[2099-01-01 00:00:00]
    end)
  end
end
