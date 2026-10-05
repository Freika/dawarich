defmodule Dawarich.Digests.JobEntriesTest do
  use Dawarich.JobsCase

  alias Dawarich.Digests.{
    MonthlyScheduleWorker,
    MonthlyWorker,
    YearlyScheduleWorker,
    YearlyWorker
  }

  alias Dawarich.Jobs.{Claimer, Registry}
  alias Dawarich.{RailsJobOwners, RailsTree, ReleaseJobs}

  test "digest registry maps four keys to unclaimable workers on exact Rails schedules without catch-up" do
    start_oban(__MODULE__)
    entries = Map.new(Registry.entries(), &{&1.key, &1})
    schedule = RailsTree.read("config/schedule.yml")

    for {type, worker, class} <- [
          {"digests.calculate_month", MonthlyWorker, "Users::Digests::Monthly::CalculatingJob"},
          {"digests.calculate_year", YearlyWorker, "Users::Digests::Yearly::CalculatingJob"}
        ] do
      key = "command:" <> type
      assert %{kind: :command, worker: ^worker, claimable: false} = entries[key]
      assert Registry.command(type) == {:ok, worker}
      payload = %{"user_id" => 1, "year" => 2025, "time_zone" => "Asia/Tokyo"}
      payload = if worker == MonthlyWorker, do: Map.put(payload, "month", 3), else: payload
      assert worker.args_from_command(1, payload) == {:ok, payload}
      assert worker.new(payload).changes.queue == "projections"
      assert RailsJobOwners.owners()[class] == {:oban, [key]}
      refute class in ReleaseJobs.classes()
    end

    for {name, expression, worker, class} <- [
          {"monthly_digest_scheduling_job", "0 4 2 * *", MonthlyScheduleWorker,
           "Users::Digests::Monthly::SchedulingJob"},
          {"yearly_digest_scheduling_job", "0 6 2 1 *", YearlyScheduleWorker,
           "Users::Digests::Yearly::SchedulingJob"}
        ] do
      key = "cron:" <> name

      assert %{kind: :cron, worker: ^worker, claimable: false, expression: ^expression} =
               entries[key]

      assert [_, ^expression] = Regex.run(~r/#{name}:\n\s+cron: "([^"]+)"/, schedule)
      assert {expression, worker} in Registry.crontab()
      assert worker.new(%{}).changes.queue == "projections"
      assert RailsJobOwners.owners()[class] == {:oban, [key]}
      refute class in ReleaseJobs.classes()
      assert Claimer.claim(ScratchRepo, __MODULE__, entries[key]) == :claimed
      assert [["oban"]] = rows("SELECT owner FROM phoenix.job_owners WHERE key=$1", [key])
      assert [[0]] = rows("SELECT count(*) FROM oban.oban_jobs")
      assert entries[key].catch_up == false
    end

    assert RailsJobOwners.owners()["Users::Digests::CalculatingJob"] ==
             {:oban, ["command:digests.calculate_year"], :retire}

    assert RailsJobOwners.owners()["Users::Digests::EmailSendingJob"] == :retire

    for {class, key, worker} <- [
          {"Users::Digests::Monthly::EmailSendingJob", "command:mail.digest.monthly",
           Dawarich.Mail.Digests.MonthlyWorker},
          {"Users::Digests::Yearly::EmailSendingJob", "command:mail.digest.yearly",
           Dawarich.Mail.Digests.YearlyWorker}
        ] do
      assert RailsJobOwners.owners()[class] == {:oban, [key]}
      assert %{kind: :command, worker: ^worker, claimable: false} = entries[key]
      refute class in ReleaseJobs.classes()
    end

    assert Registry.claimable() == []
  end

  test "digest cron firing instants retain Oban UTC and disclose Rails zone offsets" do
    {Oban, config} = Enum.find(Dawarich.Application.children(:none), &match?({Oban, _}, &1))
    cron = Keyword.fetch!(config, :cron)
    assert cron[:timezone] == "Etc/UTC"

    triggers =
      __DIR__
      |> Path.join("../../fixtures/a12d1b2/jobs.json")
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("triggers")

    for row <- triggers do
      worker = if row["kind"] == "monthly", do: MonthlyScheduleWorker, else: YearlyScheduleWorker
      assert {row["cron"], worker} in cron[:crontab]
      {:ok, after_time, 0} = DateTime.from_iso8601(row["after"])
      {:ok, rails_time, 0} = DateTime.from_iso8601(row["fires_at"])
      expr = Oban.Cron.Expression.parse!(row["cron"])

      native_time =
        expr
        |> Oban.Cron.Expression.next_at(DateTime.shift_zone!(after_time, cron[:timezone]))
        |> DateTime.shift_zone!("Etc/UTC")

      {year, month, hour} =
        if row["kind"] == "monthly" do
          {after_time.year, after_time.month, 4}
        else
          {if(after_time.month == 1, do: after_time.year, else: after_time.year + 1), 1, 6}
        end

      assert native_time == DateTime.new!(Date.new!(year, month, 2), Time.new!(hour, 0, 0))

      assert [[local]] =
               rows("SELECT $1::timestamptz AT TIME ZONE $2", [rails_time, row["resolved_zone"]])

      assert local.day == 2
      assert local.hour == hour
      assert DateTime.diff(native_time, rails_time) in [3600, 7200, 32400, 36000, 39600]
      if row["tz"], do: assert(row["resolved_zone"] == row["tz"])
    end
  end
end
