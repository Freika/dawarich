defmodule Dawarich.Cache.PreheatDigestsTest do
  use Dawarich.JobsCase

  alias Dawarich.Cache.PreheatDigests
  alias Dawarich.DigestFixtures, as: F

  test "preheat calculates missing blank and older yearly rows but keeps equal fresh and no-update rows" do
    for state <- ~w(missing blank nil false list whitespace older equal fresh no_update) do
      reset!(ScratchRepo)
      kase = F.case!("existing_yearly")
      F.load!(ScratchRepo, kase)
      opts = Keyword.delete(F.options(kase), :uuid)
      now = DateTime.to_naive(opts[:now])
      rows("UPDATE stats SET updated_at=$1 WHERE user_id=14101", [now])

      stamp =
        case state do
          "older" -> NaiveDateTime.add(now, -1)
          "fresh" -> NaiveDateTime.add(now, 1)
          _ -> now
        end

      rows("UPDATE digests SET updated_at=$1 WHERE user_id=14101", [stamp])
      expected = hd(kase["expected"]["rows"])

      rows("UPDATE digests SET travel_patterns=$1 WHERE user_id=14101", [
        expected["travel_patterns"]
      ])

      if state in ~w(blank nil false list whitespace) do
        patterns = %{
          "blank" => %{},
          "nil" => nil,
          "false" => false,
          "list" => [],
          "whitespace" => " \n"
        }

        rows("UPDATE digests SET travel_patterns=$1 WHERE user_id=14101", [patterns[state]])
      end

      if state == "missing", do: rows("DELETE FROM digests WHERE user_id=14101")
      if state == "no_update", do: rows("DELETE FROM stats WHERE user_id=14101")
      before = F.digests(ScratchRepo, 14101)
      stats = rows("SELECT id,distance,updated_at FROM stats WHERE user_id=14101 ORDER BY id")

      assert PreheatDigests.call(ScratchRepo, 14101, opts) == :ok
      [after_row] = Enum.filter(F.digests(ScratchRepo, 14101), &(&1["year"] == 2025))

      if state in ~w(equal fresh no_update) do
        assert [after_row] == before, state
      else
        assert after_row["distance"] == expected["distance"], state
        assert after_row["travel_patterns"] == expected["travel_patterns"], state
        assert after_row["updated_at"] == expected["updated_at"], state

        if before != [] do
          for key <- ~w(id sharing_uuid sharing_settings sent_at created_at flight_distance) do
            assert after_row[key] == hd(before)[key], "#{state}: #{key}"
          end
        end
      end

      assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
      assert [[0]] = rows("SELECT count(*) FROM notifications")

      assert rows("SELECT id,distance,updated_at FROM stats WHERE user_id=14101 ORDER BY id") ==
               stats
    end
  end

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
