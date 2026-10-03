defmodule Dawarich.TwoNodeHarness.CronWorker do
  @moduledoc false
  use Oban.Worker, queue: :default

  @impl Oban.Worker
  def perform(_job), do: :ok
end

defmodule Dawarich.TwoNodeHarness do
  @moduledoc false

  @name Dawarich.TwoNodeOban

  def boot(scratch_config, node, prefix \\ "oban") do
    parent = self()

    spawn(fn ->
      Application.put_env(
        :dawarich,
        Dawarich.ScratchRepo,
        Keyword.put(scratch_config, :pool_size, 1)
      )

      {:ok, _} = Application.ensure_all_started(:postgrex)
      {:ok, _} = Application.ensure_all_started(:oban)

      :ok =
        :telemetry.attach_many(
          __MODULE__,
          [[:oban, :peer, :election, :stop], [:dawarich, :scratch_repo, :query]],
          &__MODULE__.elected/4,
          parent
        )

      {:ok, supervisor} = Supervisor.start_link([Dawarich.ScratchRepo], strategy: :one_for_one)
      Dawarich.ScratchRepo.query!("SELECT 1", [], log: false)

      {:ok, _} =
        Supervisor.start_child(
          supervisor,
          {Oban,
           name: @name,
           repo: Dawarich.ScratchRepo,
           prefix: prefix,
           node: node,
           notifier: Oban.Notifiers.PG,
           peer: Oban.Peers.Database,
           stager: false,
           queues: [],
           plugins: [],
           cron: [crontab: [{"@reboot", Dawarich.TwoNodeHarness.CronWorker}]]}
        )

      send(parent, :booted)

      receive do
        :stop -> :ok
      end
    end)

    receive do
      :booted -> :ok
    end

    receive do
      {:elected, result} ->
        :telemetry.detach(__MODULE__)
        result
    end
  end

  def elected(
        [:dawarich, :scratch_repo, :query],
        _measurements,
        %{query: "commit", result: {:ok, _}},
        _parent
      ) do
    Process.put(__MODULE__, :committed)
  end

  def elected([:oban, :peer, :election, :stop], _measurements, %{conf: %{name: @name}}, parent) do
    result =
      if Process.delete(__MODULE__) == :committed, do: :ok, else: {:error, :election_failed}

    send(parent, {:elected, result})
  end

  def elected(_event, _measurements, _metadata, _parent), do: :ok

  def leader?, do: Oban.Peer.leader?(@name)

  def evaluate_cron do
    cron = Oban.Registry.whereis(@name, {:plugin, Oban.Cron})
    send(cron, :evaluate)
    :sys.get_state(cron)
    :ok
  end
end
