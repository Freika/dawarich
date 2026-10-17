defmodule Dawarich.A12f3bR07Test do
  use Dawarich.JobsCase
  alias Dawarich.DigestFixtures, as: F
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Digests.Schedule
  alias Dawarich.Mail.{ResidualCommands, Digests.Enqueue}
  @oban __MODULE__.Oban

  setup do
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

  @tag a12f3b_case: "R07k01"
  test "digests.calculate_month native producer reaches its source terminal effect" do
    for mode <- [:sidekiq, :oban], do: calculate("month", mode)
  end

  @tag a12f3b_case: "R07k02"
  test "digests.calculate_year native producer reaches its source terminal effect" do
    for mode <- [:sidekiq, :oban], do: calculate("year", mode)
  end

  @tag a12f3b_case: "R07k03"
  test "digests.email_month native producer reaches its source terminal effect" do
    for mode <- [:sidekiq, :oban], do: email("month", mode)
  end

  @tag a12f3b_case: "R07k04"
  test "digests.email_year native producer reaches its source terminal effect" do
    for mode <- [:sidekiq, :oban], do: email("year", mode)
  end

  defp calculate(period, mode) do
    reset!(ScratchRepo)

    if mode == :sidekiq,
      do: System.put_env("DAWARICH_RAILS", "off"),
      else: System.delete_env("DAWARICH_RAILS")

    Ownership.put!(ScratchRepo, "command:stats.calculate_month", mode, pinned: true)
    kind = if period == "month", do: "monthly", else: "yearly"
    kase = F.job_case!("new_#{kind}_en")
    F.load!(ScratchRepo, kase)
    args = F.job_args(kase)
    Ownership.put!(ScratchRepo, "command:digests.calculate_#{period}", mode, pinned: true)
    Ownership.put!(ScratchRepo, "command:mail.digest.#{kind}", mode, pinned: true)
    due = ~U[2026-10-03 12:00:00Z]

    for _ <- 1..2 do
      options = [oban: @oban, event_id: args["event_id"], scheduled_at: due]
      assert schedule(period, args, options) == :ok
    end

    assert [[job, at]] = rows("SELECT args, scheduled_at FROM oban.oban_jobs")
    assert NaiveDateTime.compare(at, DateTime.to_naive(due)) == :eq
    assert job["time_zone"] == args["time_zone"]

    assert rows("SELECT count(*) FROM public.job_outbox WHERE command_type LIKE 'mail.digest.%'") ==
             [[0]]

    worker =
      if period == "month",
        do: Dawarich.Digests.MonthlyWorker,
        else: Dawarich.Digests.YearlyWorker

    for _ <- 1..2, do: assert(worker.perform(%Oban.Job{args: job}, F.job_options(kase)) == :ok)
    [digest] = F.digests(ScratchRepo, args["user_id"])
    [expected] = kase["expected"]["rows"]
    assert digest == Map.put(expected, "id", digest["id"])
    assert digest["sent_at"] == nil

    assert rows("SELECT count(*) FROM public.job_outbox WHERE command_type LIKE 'mail.digest.%'") ==
             [[1]]

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    Ownership.put!(ScratchRepo, "command:digests.calculate_#{period}", :sidekiq, pinned: true)
    System.delete_env("DAWARICH_RAILS")
    assert schedule(period, args, scheduled_at: due) == :ok

    assert [[payload]] =
             rows("SELECT payload FROM phoenix.rails_commands WHERE kind=$1", [
               "digests.calculate_" <> period
             ])

    assert payload["time_zone"] == args["time_zone"]
    assert payload["run_at"] == DateTime.to_unix(due)
  end

  defp schedule("month", args, opts),
    do:
      Schedule.monthly(
        ScratchRepo,
        args["user_id"],
        args["year"],
        args["month"],
        args["time_zone"],
        opts
      )

  defp schedule("year", args, opts),
    do: Schedule.yearly(ScratchRepo, args["user_id"], args["year"], args["time_zone"], opts)

  defp email(period, mode) do
    reset!(ScratchRepo)

    if mode == :sidekiq,
      do: System.put_env("DAWARICH_RAILS", "off"),
      else: System.delete_env("DAWARICH_RAILS")

    Ownership.put!(ScratchRepo, "command:stats.calculate_month", mode, pinned: true)
    kind = if period == "month", do: "monthly", else: "yearly"
    kase = F.job_case!("existing_#{kind}_en")
    F.load!(ScratchRepo, kase)
    args = F.job_args(kase)
    id = args["user_id"]

    rows("UPDATE users SET settings=settings || $2::jsonb WHERE id=$1", [
      id,
      %{"#{kind}_digest_emails_enabled" => true}
    ])

    rows("UPDATE digests SET distance=500000, sent_at=NULL WHERE user_id=$1", [id])
    Ownership.put!(ScratchRepo, "command:mail.digest.#{kind}", mode, pinned: true)
    for _ <- 1..2, do: assert(ResidualCommands.digest(ScratchRepo, period, args) == :ok)

    assert [[payload]] =
             rows("SELECT payload FROM public.job_outbox WHERE command_type=$1", [
               "mail.digest." <> kind
             ])

    assert payload["time_zone"] == args["time_zone"]
    assert payload["locale"] == "en"
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    payload = Map.put(payload, "event_id", args["event_id"])

    assert Enqueue.run(ScratchRepo, kind, payload,
             oban: @oban,
             after_enqueue: fn -> raise "synthetic enqueue failure" end
           ) == {:error, "digest_mail_enqueue_failed"}

    assert [digest] = F.digests(ScratchRepo, id)
    assert digest["sent_at"] == nil
    rows("DELETE FROM oban.oban_jobs")
    assert Enqueue.run(ScratchRepo, kind, payload, oban: @oban) == :ok
    [sent] = F.digests(ScratchRepo, id)
    refute sent["sent_at"] == nil
    assert Enqueue.run(ScratchRepo, kind, payload, oban: @oban) == :ok
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
    Ownership.put!(ScratchRepo, "command:mail.digest.#{kind}", :sidekiq, pinned: true)
    System.delete_env("DAWARICH_RAILS")
    assert ResidualCommands.digest(ScratchRepo, period, args) == :ok
    assert rows("SELECT kind FROM phoenix.rails_commands") == [["digests.email_" <> period]]
  end
end
