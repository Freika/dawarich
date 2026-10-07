defmodule Dawarich.A12f3bE05C1Test do
  use Dawarich.JobsCase

  alias Dawarich.DigestFixtures, as: F
  alias Dawarich.Digests.{Schedule, MonthlyWorker}
  alias Dawarich.Jobs.Ownership
  @oban __MODULE__.Oban

  setup do
    start_oban(@oban)
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    Ownership.put!(ScratchRepo, "command:digests.calculate_month", :oban)
    Ownership.put!(ScratchRepo, "command:mail.digest.monthly", :oban)
    Ownership.put!(ScratchRepo, "command:stats.calculate_month", :oban)
    :ok
  end

  @tag a12f3b_case: "E05C1a"
  test "E05C1 native source shapes reach their terminal effects" do
    kase = F.job_case!("new_monthly_en")
    F.load!(ScratchRepo, kase)
    args = F.job_args(kase)
    due = ~U[2030-03-29 12:34:56.123456Z]
    opts = [oban: @oban, event_id: args["event_id"], scheduled_at: due]

    for value <- [to_string(args["year"]), args["year"]] do
      assert Schedule.monthly(ScratchRepo, args["user_id"], value, "03", args["time_zone"], opts) ==
               :ok
    end

    Ownership.put!(ScratchRepo, "cron:monthly_digest_scheduling_job", :oban)

    assert Dawarich.Digests.MonthlyScheduleWorker.perform(
             %Oban.Job{conf: %Oban.Config{name: @oban}},
             opts ++ [now: ~U[2025-04-02 12:00:00Z], zone: args["time_zone"]]
           ) == :ok

    jobs =
      rows("SELECT args, scheduled_at FROM oban.oban_jobs ORDER BY (args->>'user_id')::integer")

    assert length(jobs) == 2
    assert Enum.map(jobs, fn [child, _] -> child["user_id"] end) == [14101, 14102]

    assert Enum.all?(jobs, fn [child, at] ->
             child["event_id"] == args["event_id"] and at == DateTime.to_naive(due)
           end)

    [[job, at]] = Enum.filter(jobs, fn [child, _] -> child["user_id"] == args["user_id"] end)
    assert job == args
    assert at == DateTime.to_naive(due)

    for _ <- 1..2,
        do: assert(MonthlyWorker.perform(%Oban.Job{args: job}, F.job_options(kase)) == :ok)

    [digest] = F.digests(ScratchRepo, args["user_id"])
    [expected] = kase["expected"]["rows"]
    assert digest == Map.put(expected, "id", digest["id"])

    assert [[payload]] =
             rows("SELECT payload FROM job_outbox WHERE command_type='mail.digest.monthly'")

    assert payload["locale"] == "en"
    assert payload["time_zone"] == args["time_zone"]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end
end
