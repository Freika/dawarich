defmodule Dawarich.Users.RecalculationPeriodTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.Users.RecalculationPeriod, as: Period

  test "matches coerced years and user-local year ranges including fallback replay" do
    kase = Fixtures.case!("full")
    Fixtures.load!(ScratchRepo, kase)

    {:ok, :ok} =
      ScratchRepo.transaction(fn ->
        rows("SELECT set_config('TimeZone', 'UTC', true)")
        assert Period.years(ScratchRepo, 170_101, nil) == {:ok, [2025, 2024]}
        assert Period.years(ScratchRepo, -1, nil) == {:ok, []}

        for id <-
              ~w(user_specific user_coerced user_zero user_blank user_float user_tokyo user_dst user_invalid_zone user_nested_argument) do
          source = Fixtures.case!(id)
          [_, options] = source["job"]["arguments"]
          tracks = Enum.filter(source["expected"]["calls"], &(&1["kind"] == "tracks"))
          years = Enum.map(tracks, &hd(&1["options"]["start_at"] |> String.split("-")))

          assert Period.years(ScratchRepo, 170_101, options["year"]) ==
                   {:ok, Enum.map(years, &String.to_integer/1)}

          settings = hd(source["input"]["users"])["settings"]

          zone =
            if id == "user_nested_argument",
              do: Period.fallback_zone(ScratchRepo, %{}),
              else: Period.zone(ScratchRepo, settings, %{})

          for track <- tracks do
            {:ok, [year]} = Period.years(ScratchRepo, 170_101, options["year"])
            range = Period.bounds(ScratchRepo, year, zone)
            assert DateTime.to_unix(range.start_at) == track["start_timestamp"], id
            assert DateTime.to_unix(range.end_at) == track["end_timestamp"], id
            assert elem(range.end_at.microsecond, 0) == track["end_microsecond"], id
          end
        end

        assert Period.years(ScratchRepo, 170_101, true) == {:error, :invalid_year}

        assert Period.zone(ScratchRepo, %{"timezone" => "Unknown/Zone"}, %{
                 "TIME_ZONE" => "Asia/Tokyo"
               }) == "Asia/Tokyo"

        assert Period.zone(ScratchRepo, %{"timezone" => "Tokyo"}, %{}) == "Asia/Tokyo"
        assert Period.fallback_zone(ScratchRepo, %{}) == "Etc/UTC"

        assert Period.fallback_zone(ScratchRepo, %{"TIME_ZONE" => "Europe/Berlin"}) ==
                 "Europe/Berlin"

        :ok
      end)
  end

  test "derives source UUIDv5 separately for each year and original job id" do
    for id <- ~w(user_all user_specific) do
      source = Fixtures.case!(id)

      for track <- Enum.filter(source["expected"]["calls"], &(&1["kind"] == "tracks")) do
        year = track["options"]["start_at"] |> String.slice(0, 4) |> String.to_integer()
        assert Period.event_id(source["job"]["job_id"], year) == track["options"]["event_id"], id
      end
    end

    id = Fixtures.case!("user_all")["job"]["job_id"]
    first = Period.event_id(id, 2025)
    assert first == Period.event_id(id, 2025)
    refute first == Period.event_id(id, 2024)
    refute first == Period.event_id("00000000-0000-4000-8000-000000170003", 2025)
    assert <<_::binary-size(14), "5", _::binary>> = first
  end
end
