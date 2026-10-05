defmodule Dawarich.Jobs.ClaimerTest.InvalidJob do
  @moduledoc false
  def new(args), do: Oban.Job.new(args, worker: Dawarich.Jobs.TestEchoWorker, priority: 99)
end

defmodule Dawarich.Jobs.ClaimerTest.CronWorker do
  @moduledoc false
  use Oban.Worker, queue: :default

  @impl Oban.Worker
  def perform(_job), do: :ok
end

defmodule Dawarich.Jobs.ClaimerTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  import ExUnit.CaptureLog

  alias Dawarich.Jobs.{Claimer, Ownership, TestEchoWorker}
  alias Dawarich.Jobs.ClaimerTest.{CronWorker, InvalidJob}

  defmodule ClientErrorRepo do
    @moduledoc false
    def transaction(fun), do: {:ok, fun.()}
    def query!(_sql, _params, _opts), do: raise(Postgrex.Error, message: "client-side failure")
  end

  @oban Dawarich.ClaimerTestOban
  @command %{key: "command:test.echo", kind: :command, worker: TestEchoWorker, claimable: true}
  @cron %{
    key: "cron:test_echo",
    kind: :cron,
    expression: "* * * * *",
    worker: CronWorker,
    claimable: true
  }

  setup do
    start_oban(@oban)
    :ok
  end

  defp owner(key), do: rows("SELECT owner, pinned FROM phoenix.job_owners WHERE key = $1", [key])

  defp trail(event), do: Process.put(:trail, [event | Process.get(:trail, [])])

  defp hold(lock) do
    parent = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          lock.()
          send(parent, :holding)

          receive do
            :release -> :released
          end
        end)
      end)

    assert_receive :holding
    holder
  end

  defp contended_claim(entry) do
    claim = Task.async(fn -> Claimer.claim_all(ScratchRepo, @oban, [entry], "50ms") end)
    Task.yield(claim, 5_000) || Task.shutdown(claim, :brutal_kill)
  end

  test "empty ownership opt-in claims nothing and explicit known keys preserve operator pins" do
    for value <- [nil, "", "  "], do: assert(Claimer.entries(value) == [])
    assert Claimer.run(repo: ScratchRepo, oban: @oban, ready?: fn -> true end) == :ok
    assert rows("SELECT count(*) FROM phoenix.job_owners") == [[0]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]

    pinned = "command:visits.suggest"
    selected = "command:geocoding.reverse_point"
    Ownership.put!(ScratchRepo, pinned, :sidekiq, pinned: true)
    entries = Claimer.entries(" #{pinned}, #{selected} ")
    assert Enum.map(entries, & &1.key) == [pinned, selected]
    assert Enum.all?(entries, &(&1.claimable == false))

    assert Claimer.run(repo: ScratchRepo, oban: @oban, entries: entries, ready?: fn -> true end) ==
             :ok

    assert owner(pinned) == [["sidekiq", true]]
    assert owner(selected) == [["oban", false]]
    assert rows("SELECT count(*) FROM phoenix.job_owners") == [[2]]

    for invalid <- [
          "*",
          "command:unknown",
          "#{selected},#{selected}",
          "#{selected},",
          ",#{selected}"
        ] do
      assert_raise ArgumentError, fn -> Claimer.entries(invalid) end
    end
  end

  test "claims an unpinned key, creating a missing row first" do
    assert Claimer.claim_all(ScratchRepo, @oban, [@command]) == [{"command:test.echo", :claimed}]
    assert owner("command:test.echo") == [["oban", false]]
    assert [["claimer:" <> _]] = rows("SELECT updated_by FROM phoenix.job_owners")
  end

  test "never touches a pinned key and is idempotent" do
    :ok = Ownership.put!(ScratchRepo, @command.key, :sidekiq, pinned: true)

    assert Claimer.claim_all(ScratchRepo, @oban, [@command]) == [{"command:test.echo", :pinned}]
    assert owner("command:test.echo") == [["sidekiq", true]]

    :ok = Ownership.put!(ScratchRepo, @command.key, :oban)
    assert Claimer.claim_all(ScratchRepo, @oban, [@command]) == [{"command:test.echo", :already}]
  end

  test "a newly claimed cron key gets exactly one catch-up job and a pinned cron key none" do
    pinned = %{@cron | key: "cron:pinned_echo"}
    :ok = Ownership.put!(ScratchRepo, pinned.key, :sidekiq, pinned: true)

    assert Claimer.claim_all(ScratchRepo, @oban, [@cron, pinned]) ==
             [{"cron:test_echo", :claimed}, {"cron:pinned_echo", :pinned}]

    assert Claimer.claim_all(ScratchRepo, @oban, [@cron, pinned]) ==
             [{"cron:test_echo", :already}, {"cron:pinned_echo", :pinned}]

    assert rows("SELECT worker FROM oban.oban_jobs") == [["Dawarich.Jobs.ClaimerTest.CronWorker"]]
  end

  test "a seasonal cron entry is claimed without a catch-up job" do
    seasonal = Map.put(%{@cron | key: "cron:seasonal_echo"}, :catch_up, false)

    assert Claimer.claim_all(ScratchRepo, @oban, [seasonal]) == [{"cron:seasonal_echo", :claimed}]
    assert owner("cron:seasonal_echo") == [["oban", false]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end

  test "the catch-up job commits or rolls back with the flip" do
    assert {:error, :outer} =
             ScratchRepo.transaction(fn ->
               assert Claimer.claim(ScratchRepo, @oban, @cron) == :claimed
               ScratchRepo.rollback(:outer)
             end)

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert owner(@cron.key) == []
  end

  test "waits for a producer holding the row, reports the timeout, and claims once it is free" do
    rows("INSERT INTO phoenix.job_owners (key) VALUES ($1)", [@command.key])
    parent = self()

    holder =
      Task.async(fn ->
        Ownership.with_owner(ScratchRepo, @command.key, :sidekiq, fn ->
          send(parent, :holding)

          receive do
            :release -> :produced
          end
        end)
      end)

    assert_receive :holding

    assert contended_claim(@command) ==
             {:ok, [{"command:test.echo", {:error, :lock_not_available}}]}

    send(holder.pid, :release)
    assert Task.await(holder) == {:ok, :produced}

    assert Claimer.claim_all(ScratchRepo, @oban, [@command], "50ms") ==
             [{"command:test.echo", :claimed}]
  end

  test "the flip reads the owner row under FOR UPDATE, so even the weakest row lock holds it off" do
    rows("INSERT INTO phoenix.job_owners (key) VALUES ($1)", [@command.key])

    holder =
      hold(fn ->
        ScratchRepo.query!(
          "SELECT 1 FROM phoenix.job_owners WHERE key = $1 FOR KEY SHARE",
          [@command.key],
          log: false
        )
      end)

    assert contended_claim(@command) ==
             {:ok, [{"command:test.echo", {:error, :lock_not_available}}]}

    send(holder.pid, :release)
    assert Task.await(holder) == {:ok, :released}
    assert owner("command:test.echo") == [["sidekiq", false]]
  end

  test "creating the missing row is bounded by lock_timeout behind an uncommitted release, and the release wins" do
    holder = hold(fn -> Ownership.put!(ScratchRepo, @command.key, :sidekiq, pinned: true) end)

    assert contended_claim(@command) ==
             {:ok, [{"command:test.echo", {:error, :lock_not_available}}]}

    send(holder.pid, :release)
    assert Task.await(holder) == {:ok, :released}
    assert Claimer.claim_all(ScratchRepo, @oban, [@command]) == [{"command:test.echo", :pinned}]
    assert owner("command:test.echo") == [["sidekiq", true]]
  end

  test "a client-side Postgrex error is reported per key and never skips the remaining keys" do
    assert Claimer.claim_all(ClientErrorRepo, @oban, [@command, @cron]) ==
             [{"command:test.echo", {:error, :postgrex}}, {"cron:test_echo", {:error, :postgrex}}]
  end

  test "runs only after readiness, retrying until then" do
    {:ok, answers} = Agent.start_link(fn -> [false, false, true] end)
    ready? = fn -> Agent.get_and_update(answers, fn [head | tail] -> {head, tail} end) end

    assert Claimer.run(
             repo: ScratchRepo,
             oban: @oban,
             entries: [@command],
             ready?: ready?,
             backoff_ms: 0
           ) == :ok

    assert Agent.get(answers, & &1) == []
    assert owner("command:test.echo") == [["oban", false]]
  end

  test "the first attempt and the claim after readiness run at once; not ready polls at the base delay and only failures double it" do
    script = [false, false, :raise, :raise, false, true]
    Process.put(:script, script)

    ready? = fn ->
      trail(:attempt)
      [next | rest] = Process.get(:script)
      Process.put(:script, rest)
      if next == :raise, do: raise("readiness bug"), else: next
    end

    capture_log(fn ->
      assert Claimer.run(
               repo: ScratchRepo,
               oban: @oban,
               entries: [@command],
               ready?: ready?,
               sleep: &trail({:slept, &1})
             ) == :ok
    end)

    assert Enum.reverse(Process.get(:trail)) == [
             :attempt,
             {:slept, 30_000},
             :attempt,
             {:slept, 30_000},
             :attempt,
             {:slept, 30_000},
             :attempt,
             {:slept, 60_000},
             :attempt,
             {:slept, 30_000},
             :attempt
           ]

    assert owner("command:test.echo") == [["oban", false]]
  end

  test "a catch-up job that cannot be inserted leaves the cron key unclaimed and returns an error" do
    entry = %{@cron | key: "cron:invalid_job", worker: InvalidJob}

    assert Claimer.claim_all(ScratchRepo, @oban, [entry]) == [
             {"cron:invalid_job", {:error, :catch_up_insert}}
           ]

    assert owner("cron:invalid_job") == [["sidekiq", false]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end

  test "an unclaimed key is logged and retried with a doubling delay up to the ceiling" do
    entry = %{@cron | key: "cron:invalid_job", worker: InvalidJob}

    sleep = fn ms ->
      trail(ms)
      if length(Process.get(:trail)) == 3, do: throw(:stop)
    end

    log =
      capture_log(fn ->
        assert catch_throw(
                 Claimer.run(
                   repo: ScratchRepo,
                   oban: @oban,
                   entries: [entry],
                   ready?: fn -> true end,
                   max_backoff_ms: 60_000,
                   sleep: sleep
                 )
               ) == :stop
      end)

    assert Enum.reverse(Process.get(:trail)) == [30_000, 60_000, 60_000]
    assert log =~ "[jobs.claimer] cron:invalid_job not claimed: :catch_up_insert"
    assert owner("cron:invalid_job") == [["sidekiq", false]]
  end

  test "an exception or a throw in an attempt is logged and retried, and the claim still completes" do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    ready? = fn ->
      case Agent.get_and_update(calls, &{&1, &1 + 1}) do
        0 -> raise ArgumentError, "not a database error"
        1 -> throw(:not_a_database_error)
        _ -> true
      end
    end

    log =
      capture_log(fn ->
        assert Claimer.run(
                 repo: ScratchRepo,
                 oban: @oban,
                 entries: [@command],
                 ready?: ready?,
                 backoff_ms: 0
               ) == :ok
      end)

    assert log =~ "[jobs.claimer] attempt failed (ArgumentError)"
    assert log =~ "[jobs.claimer] attempt failed (:throw)"
    assert owner("command:test.echo") == [["oban", false]]
  end

  test "a claimer whose every attempt raises stays the same live process instead of crash-looping" do
    parent = self()

    ready? = fn ->
      send(parent, {:attempt, self()})
      raise RuntimeError, "deterministic bug"
    end

    sleep = fn _ms ->
      receive do
        :next -> :ok
      end
    end

    capture_log(fn ->
      pid =
        start_supervised!(
          {Claimer,
           repo: ScratchRepo, oban: @oban, entries: [@command], ready?: ready?, sleep: sleep}
        )

      assert_receive {:attempt, ^pid}
      send(pid, :next)
      assert_receive {:attempt, ^pid}
      assert Process.alive?(pid)
      refute_received {:attempt, _}
      :ok = stop_supervised(Claimer)
    end)
  end

  test "the claimer writes through its Oban instance's repo unless given another" do
    assert Claimer.run(
             oban: @oban,
             entries: [@command],
             ready?: fn -> true end,
             sleep: fn _ -> flunk("the claim was retried") end
           ) == :ok

    assert owner("command:test.echo") == [["oban", false]]
  end

  test "the retry delay doubles and stops at the ceiling" do
    assert Claimer.next_delay(30_000, 300_000) == 60_000
    assert Claimer.next_delay(200_000, 300_000) == 300_000
    assert Claimer.next_delay(0, 300_000) == 0
  end
end
