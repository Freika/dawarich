defmodule Dawarich.TwoNodeHarness.CronWorker do
  @moduledoc false
  use Oban.Worker, queue: :default

  @impl Oban.Worker
  def perform(_job), do: :ok
end

defmodule Dawarich.TwoNodeHarness do
  @moduledoc false

  @name Dawarich.TwoNodeOban

  def boot(scratch_config, node) do
    parent = self()

    spawn(fn ->
      Application.put_env(:dawarich, Dawarich.ScratchRepo, scratch_config)
      {:ok, _} = Application.ensure_all_started(:postgrex)
      {:ok, _} = Application.ensure_all_started(:oban)

      {:ok, _} =
        Supervisor.start_link(
          [
            Dawarich.ScratchRepo,
            {Oban,
             name: @name,
             repo: Dawarich.ScratchRepo,
             prefix: "oban",
             node: node,
             notifier: Oban.Notifiers.PG,
             peer: Oban.Peers.Database,
             stager: false,
             queues: [],
             plugins: [],
             cron: [crontab: [{"@reboot", Dawarich.TwoNodeHarness.CronWorker}]]}
          ],
          strategy: :one_for_one
        )

      send(parent, :booted)

      receive do
        :stop -> :ok
      end
    end)

    receive do
      :booted -> :ok
    end
  end

  def leader?, do: Oban.Peer.leader?(@name)

  def evaluate_cron do
    cron = Oban.Registry.whereis(@name, {:plugin, Oban.Cron})
    send(cron, :evaluate)
    :sys.get_state(cron)
    :ok
  end
end
