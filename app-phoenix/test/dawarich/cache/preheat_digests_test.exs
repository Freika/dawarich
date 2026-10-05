defmodule Dawarich.Cache.PreheatDigestsTest do
  use Dawarich.JobsCase

  alias Dawarich.Cache.PreheatDigests
  alias Dawarich.DigestFixtures, as: F

  test "missing and soft-deleted users produce no calculations or cache effects" do
    for profile <- ~w(missing_user deleted_user) do
      reset!(ScratchRepo)
      kase = F.case!("#{profile}_yearly")
      F.load!(ScratchRepo, kase)

      opts =
        Keyword.put(F.options(kase), :calculate, fn _, _, _, _ ->
          send(self(), {:unexpected_preheat, profile})
          {:ok, nil}
        end)

      assert PreheatDigests.call(ScratchRepo, 14101, opts) == :ok
      refute_receive {:unexpected_preheat, _}
      assert F.digests(ScratchRepo, 14101) == []
      assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
    end
  end

  test "a second-year failure retains the first save logs once and stops remaining work" do
    for failure_at <- [1, 2], shape <- [:return, :raise] do
      reset!(ScratchRepo)
      kase = F.case!("berlin_yearly")
      F.load!(ScratchRepo, kase)
      opts = Keyword.delete(F.options(kase), :uuid)
      failed_year = if failure_at == 1, do: 2025, else: 2024
      fault = %RuntimeError{message: "synthetic calculation failure"}

      calculate = fn repo, id, year, options ->
        send(self(), {:attempt, year})

        if year == failed_year do
          if shape == :raise, do: raise(fault), else: {:error, fault}
        else
          Dawarich.Digests.Calculation.yearly(repo, id, year, options)
        end
      end

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert PreheatDigests.call(ScratchRepo, 14101, Keyword.put(opts, :calculate, calculate)) ==
                   :ok
        end)

      assert_receive {:attempt, 2025}
      if failure_at == 2, do: assert_receive({:attempt, 2024})
      refute_receive {:attempt, _}

      assert Enum.map(F.digests(ScratchRepo, 14101), & &1["year"]) ==
               if(failure_at == 1, do: [], else: [2025])

      assert length(Regex.scan(~r/Failed to preheat insights digest/, log)) == 1
      assert log =~ "RuntimeError: synthetic calculation failure"
      refute log =~ "@"
      assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
      assert [[0]] = rows("SELECT count(*) FROM notifications")
    end
  end

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
