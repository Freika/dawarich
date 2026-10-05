defmodule Dawarich.Jobs.DrainTest do
  use Dawarich.JobsCase

  @local __MODULE__.Local
  @other __MODULE__.Other
  @observer __MODULE__.Observer

  defmodule Worker do
    use Oban.Worker, queue: :default

    @impl Oban.Worker
    def perform(%Oban.Job{id: id, args: %{"stage" => "accepted"}, conf: conf}) do
      observer = Process.whereis(Dawarich.Jobs.DrainTest.Observer)
      send(observer, {:accepted, self(), id})

      receive do
        :continue ->
          conf.repo.transaction(fn ->
            Oban.insert!(
              conf.name,
              new(%{"stage" => "successor"}, scheduled_at: DateTime.add(DateTime.utc_now(), 60))
            )

            Dawarich.RailsCommands.insert!(conf.repo, "visits.suggest", %{"user_id" => 7})
          end)

          {:snooze, 60}
      end
    end

    def perform(%Oban.Job{id: id, args: %{"stage" => stage}}) do
      send(Process.whereis(Dawarich.Jobs.DrainTest.Observer), {stage, id})
      :ok
    end
  end

  test "native shutdown pauses new local execution while preserving accepted work and durable successors" do
    Process.register(self(), @observer)

    opts = [
      testing: :disabled,
      queues: [default: 1],
      peer: false,
      stager: false,
      pruner: false,
      plugins: [],
      shutdown_grace_period: 12_000
    ]

    start_oban(@local, Keyword.put(opts, :node, "drain-local"))

    jobs =
      start_supervised!(
        {Dawarich.Jobs.Supervisor,
         node: "drain-local", oban: @local, repo: ScratchRepo, auto: false, entries: []}
      )

    accepted = Oban.insert!(@local, Worker.new(%{"stage" => "accepted"}))
    assert_receive {:accepted, worker, id}, 5_000
    assert id == accepted.id
    monitor = Process.monitor(worker)
    on_exit(fn -> if Process.alive?(worker), do: send(worker, :continue) end)
    start_oban(@other, Keyword.put(opts, :node, "drain-other"))

    assert Enum.map(Supervisor.which_children(jobs), &elem(&1, 0)) == [
             :workers,
             Dawarich.Jobs.Drain
           ]

    Supervisor.stop(jobs)

    for name <- [@local, @other] do
      :sys.get_state(Oban.Registry.whereis(name, Oban.Notifier))
      :sys.get_state(Oban.Registry.whereis(name, {:producer, "default"}))
    end

    assert %{paused: true} = Oban.check_queue(@local, queue: :default)
    assert %{paused: false} = Oban.check_queue(@other, queue: :default)

    assert rows("SELECT state FROM oban.oban_jobs WHERE id = $1", [accepted.id]) == [
             ["executing"]
           ]

    other = Oban.insert!(@other, Worker.new(%{"stage" => "other"}))
    assert_receive {"other", other_id}, 5_000
    assert other_id == other.id

    send(worker, :continue)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 5_000

    assert rows("SELECT state FROM oban.oban_jobs WHERE id = $1", [accepted.id]) == [
             ["scheduled"]
           ]

    assert rows("SELECT state FROM oban.oban_jobs WHERE args->>'stage' = 'successor'") == [
             ["scheduled"]
           ]

    assert rows("SELECT kind FROM phoenix.rails_commands") == [["visits.suggest"]]
    assert Oban.config(@local).shutdown_grace_period == 12_000
  end
end
