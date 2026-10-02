defmodule Dawarich.ZoneDstTest do
  use ExUnit.Case, async: true

  alias Dawarich.ZoneDst

  defp epoch(iso) do
    {:ok, at, 0} = DateTime.from_iso8601(iso)
    DateTime.to_unix(at)
  end

  test "dst?/3 flags daylight periods and leaves standard ones unflagged" do
    assert ZoneDst.dst?("Europe/Berlin", epoch("1990-07-01T12:00:00Z"), 7200) == true
    assert ZoneDst.dst?("Europe/Berlin", epoch("1990-01-15T12:00:00Z"), 3600) == false
  end

  test "dst?/3 does not flag a one-off change of the standard offset" do
    assert ZoneDst.dst?("Antarctica/Casey", epoch("2018-03-10T16:59:59Z"), 39_600) == false
    assert ZoneDst.dst?("Antarctica/Casey", epoch("2018-03-10T17:00:00Z"), 28_800) == false
    assert ZoneDst.dst?("Antarctica/Casey", epoch("2100-01-01T00:00:00Z"), 28_800) == false
  end

  test "dst?/3 reads the first period of a zone before its first transition" do
    assert ZoneDst.dst?("Antarctica/Rothera", epoch("1976-11-30T21:00:00Z"), 0) == false
  end

  test "dst?/3 is unknown when the zoneinfo offset is not the one PostgreSQL reports" do
    assert ZoneDst.dst?("Europe/Berlin", epoch("1990-07-01T12:00:00Z"), 3600) == nil
    assert ZoneDst.dst?("Antarctica/Casey", epoch("2018-03-10T17:00:00Z"), 39_600) == nil
  end

  test "dst?/3 is unknown past the last transition of a zone that runs on rules" do
    assert ZoneDst.dst?("Europe/Berlin", epoch("2100-07-01T12:00:00Z"), 7200) == nil
  end

  test "dst?/3 is unknown for a missing zone or a path outside the zoneinfo directory" do
    assert ZoneDst.dst?("Not/AZone", 0, 0) == nil
    assert ZoneDst.dst?("../../../../etc/hosts", 0, 0) == nil
    assert ZoneDst.dst?("../zoneinfo/Europe/Berlin", epoch("1990-07-01T12:00:00Z"), 7200) == nil
    assert ZoneDst.dst?("", 0, 0) == nil
  end

  test "parse/1 refuses a truncated or inconsistent zone file instead of raising" do
    berlin = File.read!(Path.join("/usr/share/zoneinfo", "Europe/Berlin"))

    for size <- [30, 60, div(byte_size(berlin), 2), byte_size(berlin) - 40] do
      assert ZoneDst.parse(binary_part(berlin, 0, size)) == :error
    end

    assert {:ok, _table} = ZoneDst.parse(berlin)
  end

  test "pick/2 takes the only candidate" do
    assert ZoneDst.pick("Europe/Berlin", [{1_000, 3600}]) == 1_000
  end

  test "pick/2 takes the daylight instant of a daylight-to-standard overlap" do
    assert ZoneDst.pick("Europe/Berlin", [
             {epoch("1990-09-30T00:30:00Z"), 7200},
             {epoch("1990-09-30T01:30:00Z"), 3600}
           ]) == epoch("1990-09-30T00:30:00Z")
  end

  test "pick/2 takes the later instant when both periods share one daylight flag" do
    assert ZoneDst.pick("Antarctica/Casey", [
             {epoch("2018-03-10T15:30:00Z"), 39_600},
             {epoch("2018-03-10T18:30:00Z"), 28_800}
           ]) == epoch("2018-03-10T18:30:00Z")
  end

  test "pick/2 takes the later instant when the overlap follows a zone's first period" do
    assert ZoneDst.pick("Antarctica/Rothera", [
             {epoch("1976-11-30T21:00:00Z"), 0},
             {epoch("1976-12-01T00:00:00Z"), -10_800}
           ]) == epoch("1976-12-01T00:00:00Z")
  end

  test "pick/2 falls back to the earliest instant when a flag is unknown" do
    assert ZoneDst.pick("Not/AZone", [{10, 0}, {20, 0}]) == 10

    assert ZoneDst.pick("Europe/Berlin", [
             {epoch("2100-10-31T00:30:00Z"), 7200},
             {epoch("2100-10-31T01:30:00Z"), 3600}
           ]) == epoch("2100-10-31T00:30:00Z")
  end

  test "pick/2 falls back to the earliest instant when the zoneinfo disagrees about an offset" do
    assert ZoneDst.pick("Antarctica/Casey", [
             {epoch("2018-03-10T15:30:00Z"), 39_600},
             {epoch("2018-03-10T18:30:00Z"), 25_200}
           ]) == epoch("2018-03-10T15:30:00Z")
  end
end
