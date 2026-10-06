defmodule Dawarich.A12f3bR06Test do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.Ownership
  alias Dawarich.StatsFixtures, as: F
  alias Dawarich.Stats.{CalculateMonthWorker, Schedule, StatsFullRecalculationEffects}
  @oban __MODULE__.Oban

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    F.reset!()
    start_oban(@oban)
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    :ok
  end

  @tag a12f3b_case: "R06k01"
  test "stats.calculate_month native producer reaches its source terminal effect" do
    for mode <- [:sidekiq, :oban] do
      reset!(ScratchRepo)
      F.reset!()

      if mode == :sidekiq,
        do: System.put_env("DAWARICH_RAILS", "off"),
        else: System.delete_env("DAWARICH_RAILS")

      Ownership.put!(ScratchRepo, "command:stats.calculate_month", mode, pinned: true)
      F.user!(601, %{"timezone" => "Etc/UTC"})
      F.point!(6011, 601, F.ts(2024, 3, 1))
      Ownership.put!(ScratchRepo, "command:stats.calculate_month", mode, pinned: true)
      event = Ecto.UUID.generate()

      for _ <- 1..2 do
        assert Schedule.calculate(ScratchRepo, 601, 2024, 3, false, oban: @oban, event_id: event) ==
                 :ok
      end

      assert [[args]] = rows("SELECT args FROM oban.oban_jobs")
      assert args["notify_on_failure"] == false
      assert CalculateMonthWorker.perform(%Oban.Job{args: args}) == :ok
      assert %{"year" => 2024, "month" => 3, "calculation_version" => 3} = F.stat(601, 2024, 3)
      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
      rows("DELETE FROM oban.oban_jobs")
      F.point!(6012, 601, F.ts(2024, 4, 1))

      user = %{
        id: 601,
        status: 1,
        plan: 1,
        active_until: nil,
        settings: %{"timezone" => "Etc/UTC"}
      }

      params = %{
        "point" => %{"latitude" => 52, "longitude" => 13, "revision" => 0},
        "history_scope" => %{"start_at" => "1", "end_at" => "2147483647"}
      }

      assert {:ok, 200, _} =
               Dawarich.Points.ApiPosition.update(ScratchRepo, user, 6012, params, %{
                 self_hosted?: true,
                 now: DateTime.utc_now()
               })

      assert Dawarich.Repo.query!(
               "SELECT args->>'year', args->>'month' FROM oban.oban_jobs WHERE args->>'user_id'='601'",
               [],
               log: false
             ).rows == [["2024", "4"]]

      Dawarich.Repo.query!("DELETE FROM oban.oban_jobs WHERE args->>'user_id'='601'", [],
        log: false
      )

      assert rows(
               "SELECT count(*) FROM phoenix.rails_commands WHERE kind='stats.calculate_month'"
             ) == [[0]]

      rows("DELETE FROM phoenix.rails_commands")
      Ownership.put!(ScratchRepo, "command:stats.calculate_month", :sidekiq, pinned: true)
      System.delete_env("DAWARICH_RAILS")

      assert Schedule.calculate(ScratchRepo, 601, 2024, 4, false, clock: 100, schedule_in: 5) ==
               :ok

      assert [%{"run_at" => 105, "notify_on_failure" => false}] = F.calculations()
    end
  end

  @tag a12f3b_case: "R06k02"
  test "stats.full_recalculation native producer reaches its source terminal effect" do
    for mode <- [:sidekiq, :oban] do
      reset!(ScratchRepo)
      F.reset!()

      if mode == :sidekiq,
        do: System.put_env("DAWARICH_RAILS", "off"),
        else: System.delete_env("DAWARICH_RAILS")

      Ownership.put!(ScratchRepo, "command:stats.calculate_month", mode, pinned: true)
      F.user!(602, %{})
      F.point!(6021, 602, F.ts(2024, 3, 1))
      F.point!(6022, 602, F.ts(2025, 4, 1))
      Ownership.put!(ScratchRepo, "command:stats.full_recalculation", mode, pinned: true)
      event = Ecto.UUID.generate()
      payload = %{"user_id" => 602, "source_job_id" => event, "run_at" => 100}
      assert Dawarich.State.claim(ScratchRepo, "stats_full_recalculation:user:602", 300)
      for _ <- 1..2, do: assert(StatsFullRecalculationEffects.call(ScratchRepo, payload) == :ok)

      assert [[args]] =
               rows(
                 "SELECT payload FROM public.job_outbox WHERE command_type='stats.full_recalculation'"
               )

      assert Dawarich.Stats.FullRecalculation.run(ScratchRepo, Map.put(args, "event_id", event),
               oban: @oban
             ) == :ok

      assert Dawarich.Stats.FullRecalculation.run(ScratchRepo, Map.put(args, "event_id", event),
               oban: @oban
             ) == :ok

      assert rows(
               "SELECT args->>'year', args->>'month' FROM oban.oban_jobs ORDER BY (args->>'year')::integer"
             ) == [["2024", "3"], ["2025", "4"]]

      for [args] <- rows("SELECT args FROM oban.oban_jobs"),
          do: assert(CalculateMonthWorker.perform(%Oban.Job{args: args}) == :ok)

      assert F.stat(602, 2024, 3)["calculation_version"] == 3
      assert F.stat(602, 2025, 4)["calculation_version"] == 3

      assert rows(
               "SELECT count(*) FROM phoenix.once_claims WHERE key='stats_full_recalculation:user:602'"
             ) == [[0]]

      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
      Ownership.put!(ScratchRepo, "command:stats.full_recalculation", :sidekiq, pinned: true)
      System.delete_env("DAWARICH_RAILS")
      assert StatsFullRecalculationEffects.call(ScratchRepo, payload) == :ok
      assert rows("SELECT kind FROM phoenix.rails_commands") == [["stats.full_recalculation"]]
    end
  end

  @tag a12f3b_case: "R06k03"
  test "stats.caches_invalidated native producer reaches its source terminal effect" do
    for mode <- [:sidekiq, :oban] do
      reset!(ScratchRepo)
      F.reset!()

      if mode == :sidekiq,
        do: System.put_env("DAWARICH_RAILS", "off"),
        else: System.delete_env("DAWARICH_RAILS")

      Ownership.put!(ScratchRepo, "command:stats.calculate_month", mode, pinned: true)
      F.user!(603, %{})

      keys = [
        "dawarich/user_603_total_distance",
        "dawarich/user_603_countries_visited",
        "insights/yearly_digest/603/2024/1",
        "insights/yearly_digest/603/2025/1"
      ]

      other = "insights/yearly_digest/604/2024/1"

      for key <- keys ++ [other],
          do: assert(Dawarich.RailsCache.put(key, "snapshot", expires_in: 60) == {:ok, "OK"})

      args = %{"slot" => 123, "after_id" => 0, "affected_user_ids" => [603]}

      for _ <- 1..2,
          do:
            assert(Dawarich.Geocoding.NightlySweep.run(ScratchRepo, @oban, args, env: %{}) == :ok)

      for key <- keys, do: assert(Dawarich.RailsCache.get(key) == :miss)
      assert Dawarich.RailsCache.get(other) == {:ok, "snapshot"}
      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
      F.stat!(6031, 603, 2024, 3)
      for key <- keys, do: Dawarich.RailsCache.put(key, "snapshot", expires_in: 60)
      account = Dawarich.Stats.Accounts.find(ScratchRepo, 603)
      assert Dawarich.Stats.RefreshToponyms.call(ScratchRepo, account, 2024, 3, true)
      assert Dawarich.RailsCache.get(Enum.at(keys, 0)) == {:ok, "snapshot"}
      assert Dawarich.RailsCache.get(Enum.at(keys, 1)) == :miss
      assert Dawarich.RailsCache.get(Enum.at(keys, 2)) == :miss
      assert Dawarich.RailsCache.get(Enum.at(keys, 3)) == {:ok, "snapshot"}
      Ownership.put!(ScratchRepo, "command:stats.calculate_month", :sidekiq, pinned: true)
      System.delete_env("DAWARICH_RAILS")

      assert Dawarich.Geocoding.NightlySweep.run(ScratchRepo, @oban, %{args | "slot" => 124},
               env: %{}
             ) == :ok

      assert rows("SELECT kind FROM phoenix.rails_commands") == [["stats.caches_invalidated"]]
      for key <- keys ++ [other], do: Dawarich.Redis.cache_command(["DEL", key])
    end
  end

  @tag a12f3b_case: "R06k04"
  test "airtrail_stats native producer reaches its source terminal effect" do
    for mode <- [:sidekiq, :oban] do
      reset!(ScratchRepo)
      F.reset!()

      if mode == :sidekiq,
        do: System.put_env("DAWARICH_RAILS", "off"),
        else: System.delete_env("DAWARICH_RAILS")

      Ownership.put!(ScratchRepo, "command:stats.calculate_month", mode, pinned: true)
      F.user!(604, %{"timezone" => "Asia/Tokyo"})

      flights = [
        %{
          "id" => 1,
          "date" => "2024-03-01",
          "from" => %{"lat" => 0, "lon" => 0},
          "to" => %{"lat" => 0, "lon" => 1}
        }
      ]

      event = Ecto.UUID.generate()

      for _ <- 1..2,
          do:
            assert(
              Dawarich.AirTrail.Flights.store(ScratchRepo, 604, flights, event, "Etc/UTC",
                oban: @oban
              ) == :ok
            )

      assert rows("SELECT args->>'year', args->>'month' FROM oban.oban_jobs") == [["2024", "3"]]
      F.stat!(6041, 604, 2024, 3)

      for [args] <- rows("SELECT args FROM oban.oban_jobs"),
          do: assert(CalculateMonthWorker.perform(%Oban.Job{args: args}) == :ok)

      assert F.stat(604, 2024, 3)["flight_distance"] > 0
      rows("DELETE FROM oban.oban_jobs")
      changed = [%{hd(flights) | "date" => "2025-04-01"}]

      assert Dawarich.AirTrail.Flights.store(
               ScratchRepo,
               604,
               changed,
               Ecto.UUID.generate(),
               "Etc/UTC",
               oban: @oban
             ) == :ok

      assert rows(
               "SELECT args->>'year', args->>'month' FROM oban.oban_jobs ORDER BY (args->>'year')::integer"
             ) == [["2024", "3"], ["2025", "4"]]

      rows("DELETE FROM oban.oban_jobs")
      undated = [%{"id" => 2, "departure" => "2024-03-31T23:30:00Z"}]

      assert Dawarich.AirTrail.Flights.store(
               ScratchRepo,
               604,
               undated,
               Ecto.UUID.generate(),
               "Etc/UTC",
               oban: @oban
             ) == :ok

      assert rows(
               "SELECT args->>'year', args->>'month' FROM oban.oban_jobs ORDER BY (args->>'year')::integer"
             ) == [["2024", "4"], ["2025", "4"]]

      rows("DELETE FROM oban.oban_jobs")

      assert Dawarich.AirTrail.Flights.store(
               ScratchRepo,
               604,
               [],
               Ecto.UUID.generate(),
               "Etc/UTC",
               oban: @oban
             ) == :ok

      assert rows("SELECT args->>'year', args->>'month' FROM oban.oban_jobs") == [["2024", "4"]]
      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
      Ownership.put!(ScratchRepo, "command:stats.calculate_month", :sidekiq, pinned: true)
      System.delete_env("DAWARICH_RAILS")

      assert Dawarich.AirTrail.Flights.store(
               ScratchRepo,
               604,
               [],
               Ecto.UUID.generate(),
               "Etc/UTC",
               oban: @oban
             ) == :ok

      assert rows("SELECT kind FROM phoenix.rails_commands") == [["airtrail_stats"]]
    end
  end
end
