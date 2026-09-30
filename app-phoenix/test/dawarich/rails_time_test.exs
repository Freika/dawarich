defmodule Dawarich.RailsTimeTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.RailsTime

  setup do
    previous = System.get_env("TIME_ZONE")
    System.delete_env("TIME_ZONE")

    on_exit(fn ->
      if previous, do: System.put_env("TIME_ZONE", previous), else: System.delete_env("TIME_ZONE")
    end)
  end

  test "zones abbreviated UTC end in Z; another zero offset keeps +00:00" do
    assert RailsTime.iso8601(~N[2026-12-01 10:00:00], "UTC") == {:ok, "2026-12-01T10:00:00Z"}
    assert RailsTime.iso8601(~N[2026-12-01 10:00:00], "Etc/UTC") == {:ok, "2026-12-01T10:00:00Z"}

    assert RailsTime.iso8601(~N[2027-01-15 10:00:00], "Europe/London") ==
             {:ok, "2027-01-15T10:00:00+00:00"}
  end

  test "local time and offset at the instant, seconds truncated" do
    assert RailsTime.iso8601(~N[2027-07-01 10:00:00], "Europe/Berlin") ==
             {:ok, "2027-07-01T12:00:00+02:00"}

    assert RailsTime.iso8601(~N[2027-01-15 10:00:00], "America/New_York") ==
             {:ok, "2027-01-15T05:00:00-05:00"}

    assert RailsTime.iso8601(~N[2027-03-01 10:00:00.987654], "Asia/Kolkata") ==
             {:ok, "2027-03-01T15:30:00+05:30"}
  end

  test "after TZInfo's last generated year the offset in force at that year's end holds" do
    horizon = Date.utc_today().year + 100
    {:ok, inside} = NaiveDateTime.new(horizon, 7, 1, 10, 0, 0)
    {:ok, beyond} = NaiveDateTime.new(horizon + 1, 7, 1, 10, 0, 0)

    assert RailsTime.iso8601(inside, "Europe/Berlin") == {:ok, "#{horizon}-07-01T12:00:00+02:00"}

    assert RailsTime.iso8601(beyond, "Europe/Berlin") ==
             {:ok, "#{horizon + 1}-07-01T11:00:00+01:00"}

    assert RailsTime.iso8601(~N[3026-07-01 12:00:00], "Australia/Sydney") ==
             {:ok, "3026-07-01T23:00:00+11:00"}
  end

  test "no setting reads TIME_ZONE, then UTC; no time is nil whatever the setting" do
    assert RailsTime.iso8601(~N[2027-01-15 10:00:00], nil) == {:ok, "2027-01-15T10:00:00Z"}
    System.put_env("TIME_ZONE", "Europe/London")
    assert RailsTime.iso8601(~N[2027-01-15 10:00:00], nil) == {:ok, "2027-01-15T10:00:00+00:00"}
    assert RailsTime.iso8601(nil, 42) == {:ok, nil}
  end

  test "Rails aliases resolve to their IANA zone; other spellings, shapes and unknown zones go to Rails" do
    assert RailsTime.iso8601(~N[2027-07-01 10:00:00], "Berlin") ==
             {:ok, "2027-07-01T12:00:00+02:00"}

    assert RailsTime.iso8601(~N[2027-01-15 10:00:00], "Eastern Time (US & Canada)") ==
             {:ok, "2027-01-15T05:00:00-05:00"}

    for setting <- ["europe/berlin", "Europe/berlin", "UTC+3", "", 1, true, "Mars/Olympus_Mons"],
        do:
          assert(
            {:replay, _} = RailsTime.iso8601(~N[2027-01-15 10:00:00], setting),
            inspect(setting)
          )

    assert RailsTime.iso8601(~N[2027-07-01 10:00:00], "Europe/Berlin") ==
             {:ok, "2027-07-01T12:00:00+02:00"}
  end
end
