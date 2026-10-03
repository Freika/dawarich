defmodule Dawarich.UserTimeZoneIanaTest do
  use Dawarich.JobsCase

  alias Dawarich.UserTimeZone

  test "a Rails zone name maps to its IANA name, an IANA name stays, an unknown name is Etc/UTC" do
    env = %{"TIME_ZONE" => "Europe/Berlin"}
    assert UserTimeZone.iana(ScratchRepo, %{"timezone" => "Tokyo"}, env) == "Asia/Tokyo"

    assert UserTimeZone.iana(ScratchRepo, %{"timezone" => "America/New_York"}, env) ==
             "America/New_York"

    assert UserTimeZone.iana(ScratchRepo, %{"timezone" => "Mars/Olympus"}, env) == "Etc/UTC"
  end

  test "a missing zone is TIME_ZONE or UTC; a blank one is TIME_ZONE or Europe/Berlin, as Rails reads them" do
    assert UserTimeZone.iana(ScratchRepo, %{}, %{}) == "Etc/UTC"
    assert UserTimeZone.iana(ScratchRepo, %{}, %{"TIME_ZONE" => "Asia/Tokyo"}) == "Asia/Tokyo"

    assert UserTimeZone.iana(ScratchRepo, %{"timezone" => " "}, %{"TIME_ZONE" => "Asia/Tokyo"}) ==
             "Asia/Tokyo"

    assert UserTimeZone.iana(ScratchRepo, %{"timezone" => ""}, %{}) == "Europe/Berlin"
  end
end
