defmodule Dawarich.UserTimeZoneTest do
  use ExUnit.Case, async: false

  alias Dawarich.UserTimeZone

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    previous = System.get_env("TIME_ZONE")
    System.put_env("TIME_ZONE", "America/New_York")

    on_exit(fn ->
      if previous, do: System.put_env("TIME_ZONE", previous), else: System.delete_env("TIME_ZONE")
    end)
  end

  test "zone/2 prefers the setting, else the given env's TIME_ZONE, else UTC; the default still reads the process env" do
    assert UserTimeZone.zone(%{"timezone" => "Europe/Berlin"}, %{"TIME_ZONE" => "Asia/Kolkata"}) ==
             "Europe/Berlin"

    assert UserTimeZone.zone(%{}, %{"TIME_ZONE" => "Asia/Kolkata"}) == "Asia/Kolkata"
    assert UserTimeZone.zone(%{}, %{}) == "UTC"
    assert UserTimeZone.zone(%{}) == "America/New_York"
  end

  test "query!/4 validates the effective zone against a given env; the default still reads the process env" do
    assert %{rows: [["Asia/Kolkata"]]} =
             UserTimeZone.query!("SELECT z.name FROM z", [], %{}, %{"TIME_ZONE" => "Asia/Kolkata"})

    assert %{rows: [["America/New_York"]]} = UserTimeZone.query!("SELECT z.name FROM z", [], %{})
  end

  test "validated names are reused without SQL and changes to settings or env stay visible" do
    Dawarich.TimeZoneNames.invalidate(Dawarich.Repo)
    assert UserTimeZone.name(%{"timezone" => "Tokyo"}) == "Asia/Tokyo"
    id = {__MODULE__, make_ref()}
    owner = self()

    :telemetry.attach(
      id,
      [:dawarich, :repo, :query],
      fn _, _, metadata, _ ->
        send(owner, {:timezone_query, metadata.query})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)

    for _ <- 1..10 do
      assert UserTimeZone.name(%{"timezone" => "Tokyo"}) == "Asia/Tokyo"
      assert UserTimeZone.name(%{"timezone" => "Europe/Berlin"}) == "Europe/Berlin"
      assert UserTimeZone.name(%{"timezone" => "Mars/Olympus"}) == "America/New_York"
      assert UserTimeZone.iana(Dawarich.Repo, %{"timezone" => "Mars/Olympus"}) == "Etc/UTC"
    end

    System.put_env("TIME_ZONE", "Asia/Kolkata")
    assert UserTimeZone.name(%{}) == "Asia/Kolkata"
    refute_receive {:timezone_query, _}
    Dawarich.TimeZoneNames.invalidate(Dawarich.Repo)
    assert UserTimeZone.name(%{}) == "Asia/Kolkata"
    assert_receive {:timezone_query, "SELECT name FROM pg_timezone_names"}
    refute_receive {:timezone_query, _}
  end

  test "SQL parameter positions, invalid fallbacks and seasonal offsets are preserved" do
    assert %{rows: [[42, "UTC"]]} =
             UserTimeZone.query!(
               "SELECT $1::int, z.name FROM z",
               [42],
               %{"timezone" => "Mars/Olympus"},
               Dawarich.Repo,
               %{"TIME_ZONE" => "invalid"}
             )

    settings = %{"timezone" => "Europe/Berlin"}
    assert UserTimeZone.local(settings, ~N[2026-01-01 00:00:00]).offset == 3600
    assert UserTimeZone.local(settings, ~N[2026-07-01 00:00:00]).offset == 7200
  end
end
