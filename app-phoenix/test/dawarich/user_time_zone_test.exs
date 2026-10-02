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
end
