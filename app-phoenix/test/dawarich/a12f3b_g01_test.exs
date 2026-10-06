defmodule Dawarich.A12f3bG01Test do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Claimer, Drain, Ownership, Registry}

  defmodule RollbackRepo do
    def transaction(_fun), do: {:error, :source_read_failed}
  end

  @oban __MODULE__.Oban

  setup do
    start_oban(@oban)

    for name <- ~w(DAWARICH_RAILS TIME_ZONE TZ) do
      previous = System.get_env(name)

      on_exit(fn ->
        if previous, do: System.put_env(name, previous), else: System.delete_env(name)
      end)
    end

    :ok
  end

  @tag a12f3b_case: "G01a"
  test "native cron lease preserves source slot owner and catch-up policy" do
    source = File.read!(Path.expand("../../../config/schedule.yml", __DIR__))
    schedules = Regex.scan(~r/^([a-z_]+):\n  cron: "([^"]+)"/m, source)
    crons = Enum.filter(Registry.entries(), &(&1.kind == :cron))
    assert length(schedules) == 24
    assert length(crons) == 24
    assert length(Enum.uniq_by(crons, & &1.worker)) == 24

    for [_, name, expression] <- schedules do
      entry = Enum.find(crons, &(&1.key == "cron:" <> name))
      assert entry.expression == expression
      assert entry.catch_up == false
      assert entry.claimable == false
      assert {expression, entry.worker} in Registry.crontab()

      assert Ownership.with_owner(ScratchRepo, entry.key, :oban, fn -> flunk("missing owner") end) ==
               {:skip, :sidekiq}

      Ownership.put!(ScratchRepo, entry.key, :sidekiq, pinned: true)
      assert Claimer.claim(ScratchRepo, @oban, entry) == :pinned

      assert rows("SELECT owner,pinned FROM phoenix.job_owners WHERE key=$1", [entry.key]) == [
               ["sidekiq", true]
             ]

      Ownership.put!(ScratchRepo, entry.key, :sidekiq)
      assert Claimer.claim(ScratchRepo, @oban, entry) == :claimed
      assert Claimer.claim(ScratchRepo, @oban, entry) == :already
    end

    assert Claimer.claim(RollbackRepo, @oban, hd(crons)) == {:error, :source_read_failed}
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert Dawarich.Standalone.job_entries(%{"DAWARICH_RAILS" => "off"}) == Registry.entries()
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("TIME_ZONE", "Berlin")
    System.delete_env("TZ")
    assert cron_timezone() == "Europe/Berlin"
    assert Oban.Cron.validate(timezone: cron_timezone(), crontab: Registry.crontab()) == :ok
    assert {:gap, _, _} = DateTime.from_naive(~N[2026-03-29 02:30:00], cron_timezone())

    assert {:ambiguous, first, second} =
             DateTime.from_naive(~N[2026-10-25 02:30:00], cron_timezone())

    assert DateTime.diff(second, first) == 3600

    for {at, expected} <- [
          {~U[2026-01-10 00:00:00Z], ~U[2026-01-10 00:15:00Z]},
          {~U[2026-07-10 00:00:00Z], ~U[2026-07-10 23:15:00Z]}
        ] do
      {:ok, expression} = Oban.Cron.Expression.parse("15 1 * * *")
      local = DateTime.shift_zone!(at, cron_timezone())
      due = Oban.Cron.Expression.next_at(expression, local)
      assert DateTime.compare(due, expected) == :eq
    end

    System.put_env("TZ", "Asia/Tokyo")
    assert cron_timezone() == "Asia/Tokyo"

    for invalid <- ["", "Invalid/Zone"] do
      System.put_env("TZ", invalid)
      assert cron_timezone() == "Europe/Berlin"
    end

    System.delete_env("DAWARICH_RAILS")
    assert cron_timezone() == "Etc/UTC"
    status = Drain.status(ScratchRepo)
    assert "heartbeat_invalid" in status.forward_reasons

    rows(
      "INSERT INTO phoenix.runtime_nodes(node,started_at,beat_at) VALUES ('cron-contract',now(),now())"
    )

    refute "heartbeat_invalid" in Drain.status(ScratchRepo).forward_reasons
  end

  defp cron_timezone do
    {Oban, opts} = Enum.find(Dawarich.Application.children(:none), &match?({Oban, _}, &1))
    opts[:cron][:timezone]
  end
end
