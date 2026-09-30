defmodule Dawarich.LocalTimeTest do
  use ExUnit.Case, async: false

  alias Dawarich.LocalTime

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    previous = System.get_env("TIME_ZONE")
    System.delete_env("TIME_ZONE")

    on_exit(fn ->
      if previous, do: System.put_env("TIME_ZONE", previous), else: System.delete_env("TIME_ZONE")
    end)
  end

  test "the zone follows Rails' zone-name MAPPING for the setting, else TIME_ZONE, else Europe/Berlin; today is local" do
    now = ~U[2026-02-28 23:30:00Z]

    assert LocalTime.local(%{"timezone" => "Pacific/Kiritimati"}, now) ==
             {"Pacific/Kiritimati", ~D[2026-03-01]}

    assert LocalTime.local(%{"timezone" => "Berlin"}, now) == {"Europe/Berlin", ~D[2026-03-01]}
    assert LocalTime.local(%{}, now) == {"Etc/UTC", ~D[2026-02-28]}

    assert LocalTime.local(%{"timezone" => "Nowhere/Else"}, now) ==
             {"Europe/Berlin", ~D[2026-03-01]}

    System.put_env("TIME_ZONE", "America/New_York")

    assert LocalTime.local(%{"timezone" => "Nowhere/Else"}, now) ==
             {"America/New_York", ~D[2026-02-28]}
  end

  test "day bounds are Rails' TimeWithZone strings, across a DST change and for UTC" do
    assert LocalTime.day_bounds("Europe/Berlin", ~D[2024-03-07]) ==
             {"2024-03-07 00:00:00 +0100", "2024-03-07 23:59:59 +0100"}

    assert LocalTime.day_bounds("Europe/Berlin", ~D[2024-03-31]) ==
             {"2024-03-31 00:00:00 +0100", "2024-03-31 23:59:59 +0200"}

    assert LocalTime.day_bounds("America/New_York", ~D[2024-03-07]) ==
             {"2024-03-07 00:00:00 -0500", "2024-03-07 23:59:59 -0500"}

    assert LocalTime.day_bounds("UTC", ~D[2024-03-07]) ==
             {"2024-03-07 00:00:00 UTC", "2024-03-07 23:59:59 UTC"}

    assert LocalTime.day_bounds("Europe/London", ~D[2024-01-07]) ==
             {"2024-01-07 00:00:00 +0000", "2024-01-07 23:59:59 +0000"}
  end
end
