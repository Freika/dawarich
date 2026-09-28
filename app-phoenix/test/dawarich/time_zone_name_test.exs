defmodule Dawarich.TimeZoneNameTest do
  use ExUnit.Case, async: true

  alias Dawarich.TimeZoneName

  @table Path.expand("../../priv/time_zone_names.json", __DIR__)

  test "an ActiveSupport name maps to the IANA zone of ActiveSupport::TimeZone::MAPPING" do
    assert TimeZoneName.to_iana("Berlin") == "Europe/Berlin"
    assert TimeZoneName.to_iana("Eastern Time (US & Canada)") == "America/New_York"
    assert TimeZoneName.to_iana("UTC") == "Etc/UTC"
    assert TimeZoneName.to_iana("Newfoundland") == "America/St_Johns"
  end

  test "an IANA name passes through unchanged" do
    for name <- ~w(Europe/Berlin America/St_Johns Etc/UTC Pacific/Chatham) do
      assert TimeZoneName.to_iana(name) == name
    end
  end

  test "a name outside ActiveSupport's mapping passes through for PostgreSQL to validate" do
    assert TimeZoneName.to_iana("Nowhere/Land") == "Nowhere/Land"

    assert_raise Postgrex.Error, ~r/time zone "Nowhere\/Land" not recognized/, fn ->
      Dawarich.ScratchRepo.query!("SELECT now() AT TIME ZONE $1", [
        TimeZoneName.to_iana("Nowhere/Land")
      ])
    end
  end

  test "every mapped zone is known to PostgreSQL" do
    mapped = @table |> File.read!() |> Jason.decode!() |> Map.fetch!("mapping") |> Map.values()
    assert length(mapped) == 152

    known =
      Dawarich.ScratchRepo.query!(
        "SELECT name FROM pg_timezone_names WHERE name = ANY($1)",
        [Enum.uniq(mapped)],
        log: false
      ).rows
      |> List.flatten()

    assert Enum.uniq(mapped) -- known == []
  end
end
