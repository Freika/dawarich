defmodule Dawarich.Metrics.JobsTest do
  use Dawarich.JobsCase, async: false
  @moduletag :capture_log

  defmodule Worker do
    use Oban.Worker, queue: :maintenance
    def perform(%Oban.Job{args: %{"fail" => true}}), do: raise("synthetic job failure")
    def perform(_), do: :ok
  end

  defmodule UnavailableRepo do
    def transaction(_), do: raise("synthetic collection failure")
  end

  setup do
    start_supervised!(Dawarich.Metrics)
    :ok
  end

  test "native job lifecycle and pending future retry debt produce equivalent job metrics" do
    name = __MODULE__.Oban
    start_oban(name)
    Oban.insert!(name, Worker.new(%{"fail" => false}))
    Oban.insert!(name, Worker.new(%{"fail" => true}))
    assert %{success: 1, failure: 1} = Oban.drain_queue(name, queue: :maintenance)
    outbox!(scheduled_at: DateTime.add(DateTime.utc_now(), -600))
    outbox!(scheduled_at: DateTime.add(DateTime.utc_now(), 3600))

    Oban.insert!(
      name,
      Dawarich.ReleaseOperations.PointBackfill.new(
        %{"version" => 1, "event_id" => Ecto.UUID.generate(), "cursor" => %{}},
        scheduled_at: DateTime.add(DateTime.utc_now(), 3600)
      )
    )

    Dawarich.Metrics.Jobs.sample(ScratchRepo, ScratchRepo)
    body = Dawarich.Metrics.scrape()
    assert body =~ "dawarich_jobs_executed_total"
    assert body =~ "dawarich_jobs_success_total"

    assert body =~
             ~s(dawarich_jobs_failed_total{queue="maintenance",worker="Dawarich.Metrics.JobsTest.Worker"} 1)

    assert body =~ "dawarich_jobs_runtime_seconds_count"
    assert body =~ "dawarich_jobs_latency_seconds_count"
    assert body =~ ~s(dawarich_jobs_depth{queue="maintenance",state="retryable"} 1)
    assert body =~ ~s(dawarich_jobs_depth{queue="maintenance",state="scheduled"} 1)
    assert body =~ ~s(dawarich_outbox_debt{state="due"} 1)
    assert body =~ ~s(dawarich_outbox_debt{state="scheduled"} 1)
    assert body =~ "dawarich_outbox_oldest_due_seconds"
    assert body =~ "dawarich_jobs_busy"
    assert body =~ "dawarich_jobs_queue_latency_seconds"
    refute body =~ "synthetic job failure"
    refute body =~ "event_id"
    Dawarich.Metrics.Jobs.sample(UnavailableRepo, ScratchRepo)
    assert Dawarich.Metrics.scrape() =~ ~s(dawarich_outbox_debt{state="due"} 1)
    rows("UPDATE oban.oban_jobs SET state='completed'")
    rows("DELETE FROM public.job_outbox")
    Dawarich.Metrics.Jobs.sample(ScratchRepo, ScratchRepo)
    reset = Dawarich.Metrics.scrape()
    assert reset =~ ~s(dawarich_jobs_depth{queue="maintenance",state="retryable"} 0)
    assert reset =~ "dawarich_outbox_oldest_due_seconds 0"
  end

  test "Cloud drain scrape has unique series and survives source exporter failure" do
    local =
      "# HELP shared Same metric\n# TYPE shared gauge\nshared{queue=\"default\"} 1\nonly_local 2\n"

    remote =
      "# HELP shared Same metric\n# TYPE shared gauge\nshared{queue=\"default\"} 3\nonly_remote 4\n"

    config = %{
      url: "http://127.0.0.1:1/metrics",
      username: "synthetic-user",
      password: "synthetic-password"
    }

    fetch = fn ^config -> {:ok, remote} end
    body = Dawarich.Metrics.Drain.scrape(local, config, fetch)
    assert body =~ ~s(shared{process="web",queue="default"} 1)
    assert body =~ ~s(shared{process="sidekiq",queue="default"} 3)
    assert length(Regex.scan(~r/# HELP shared /, body)) == 1
    assert length(Regex.scan(~r/# TYPE shared /, body)) == 1
    assert body =~ "only_remote 4"

    assert Dawarich.Metrics.Drain.scrape(local, config, fn _ -> {:error, :unavailable} end) ==
             local

    assert Dawarich.Metrics.Drain.scrape(local, config, fn _ -> raise "offline" end) == local
  end
end
