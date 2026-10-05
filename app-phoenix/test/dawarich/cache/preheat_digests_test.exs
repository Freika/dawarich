defmodule Dawarich.Cache.PreheatDigestsTest do
  use Dawarich.JobsCase

  alias Dawarich.Cache.PreheatDigests
  alias Dawarich.DigestFixtures, as: F

  test "selects only the latest two distinct completed years in the ambient zone" do
    corpus =
      "test/fixtures/a12d1b4/cache.json"
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("completed_years")

    for kase <- corpus do
      reset!(ScratchRepo)
      F.load!(ScratchRepo, F.job_case!("new_yearly_en"))
      rows("UPDATE users SET settings=jsonb_build_object('timezone','Asia/Tokyo') WHERE id=14101")
      rows("DELETE FROM stats WHERE user_id=14101")

      for {year, month} <- [{2026, 1}, {2025, 1}, {2025, 2}, {2023, 1}, {2022, 1}] do
        rows(
          "INSERT INTO stats(user_id,year,month,distance,daily_distance,toponyms,created_at,updated_at) " <>
            "VALUES(14101,$1,$2,1000,'{}','[]','2026-10-03 12:00:00','2026-10-03 12:00:00')",
          [year, month]
        )
      end

      {:ok, now, 0} = DateTime.from_iso8601(kase["now"])
      zone = kase["ambient_zone"]

      calculate = fn repo, id, year, opts ->
        assert repo == ScratchRepo
        assert id == 14101
        assert opts[:now] == now
        assert opts[:ambient_zone] == zone
        send(self(), {:calculated, year})
        {:ok, nil}
      end

      assert PreheatDigests.call(ScratchRepo, 14101,
               now: now,
               ambient_zone: zone,
               calculate: calculate
             ) == :ok

      for year <- kase["years"], do: assert_receive({:calculated, ^year})
      refute_receive {:calculated, _}
    end
  end
end
