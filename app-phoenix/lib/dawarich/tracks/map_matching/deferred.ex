defmodule Dawarich.Tracks.MapMatching.Deferred do
  use GenServer
  require Logger
  alias Dawarich.Tracks.MapMatching.Enqueuer
  @timeout 100

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    repo = Keyword.get(opts, :repo, Dawarich.Repo)
    Dawarich.Experimental.refresh_map_matching(repo)
    {:ok, %{}}
  rescue
    _ ->
      :persistent_term.put(
        {Dawarich.Experimental, Keyword.get(opts, :repo, Dawarich.Repo), :map_matching},
        false
      )

      Logger.warning("map_matching.cache_refresh_failed")
      {:ok, %{}}
  catch
    _, _ ->
      :persistent_term.put(
        {Dawarich.Experimental, Keyword.get(opts, :repo, Dawarich.Repo), :map_matching},
        false
      )

      Logger.warning("map_matching.cache_refresh_failed")
      {:ok, %{}}
  end

  def call(repo, id) do
    caller = self()
    token = make_ref()
    handler = {__MODULE__, token}
    transaction? = repo.in_transaction?()

    if transaction? do
      :ok =
        :telemetry.attach(
          handler,
          repo.config()[:telemetry_prefix] ++ [:query],
          &__MODULE__.transaction/4,
          {caller, token}
        )
    end

    case Process.whereis(__MODULE__) do
      nil ->
        :telemetry.detach(handler)
        failure(id)
        :error

      server ->
        GenServer.cast(server, {:dispatch, token, repo, id, caller, transaction?, handler})
        :deferred
    end
  rescue
    _ ->
      failure(id)
      :error
  catch
    _, _ ->
      failure(id)
      :error
  end

  def transaction(_, _, meta, {caller, token}) do
    if self() == caller do
      case {String.downcase(to_string(meta.query)), meta.result} do
        {"commit", {:ok, _}} -> GenServer.cast(__MODULE__, {:outcome, token, :execute})
        {"commit", _} -> GenServer.cast(__MODULE__, {:outcome, token, :abort})
        {"rollback", _} -> GenServer.cast(__MODULE__, {:outcome, token, :abort})
        _ -> :ok
      end
    end
  end

  @impl true
  def handle_call(:busy?, _, state), do: {:reply, map_size(state) > 0, state}

  @impl true
  def handle_cast({:dispatch, token, repo, id, caller, transaction?, handler}, state) do
    server = self()
    {pid, monitor} = spawn_monitor(fn -> request(server, token, repo, id) end)

    entry = %{
      pid: pid,
      monitor: monitor,
      caller: if(transaction?, do: Process.monitor(caller), else: nil),
      handler: handler,
      id: id,
      ready: false,
      outcome: if(transaction?, do: :waiting, else: :execute),
      timer: Process.send_after(self(), {:timeout, token}, @timeout)
    }

    {:noreply, Map.put(state, token, entry)}
  end

  def handle_cast({:outcome, token, outcome}, state) do
    case state[token] do
      nil -> {:noreply, state}
      entry -> {:noreply, finish(Map.put(state, token, %{entry | outcome: outcome}), token)}
    end
  end

  @impl true
  def handle_info({:started, token, {:ok, _}}, state) do
    case state[token] do
      nil ->
        {:noreply, state}

      entry ->
        Process.cancel_timer(entry.timer)
        {:noreply, finish(Map.put(state, token, %{entry | ready: true}), token)}
    end
  end

  def handle_info({:started, token, _}, state), do: {:noreply, failed(state, token)}

  def handle_info({:timeout, token}, state) do
    case state[token] do
      %{ready: false} -> {:noreply, failed(state, token)}
      _ -> {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _, _}, state) do
    case Enum.find(state, fn {_, entry} -> ref in [entry.monitor, entry.caller] end) do
      nil -> {:noreply, state}
      {token, %{caller: ^ref}} -> {:noreply, cleanup(state, token)}
      {token, _} -> {:noreply, failed(state, token)}
    end
  end

  @impl true
  def terminate(_, state) do
    Enum.each(state, fn {token, _} -> cleanup(state, token) end)
    :ok
  end

  defp request(server, token, repo, id) do
    requester = self()

    result =
      try do
        Task.Supervisor.start_child(Dawarich.Tracks.MapMatching.Tasks, fn ->
          monitor = Process.monitor(requester)

          receive do
            :execute ->
              Process.demonitor(monitor, [:flush])
              result = Enqueuer.call(repo, id)

              :telemetry.execute([:dawarich, :map_matching, :hook], %{}, %{
                track_id: id,
                result: result
              })

            {:DOWN, ^monitor, :process, ^requester, _} ->
              :ok
          end
        end)
      rescue
        _ -> :error
      catch
        _, _ -> :error
      end

    send(server, {:started, token, result})

    if match?({:ok, _}, result) do
      {:ok, pid} = result
      monitor = Process.monitor(server)

      receive do
        :execute -> send(pid, :execute)
        :abort -> :ok
        {:DOWN, ^monitor, :process, ^server, _} -> :ok
      end
    end
  end

  defp finish(state, token) do
    case state[token] do
      %{ready: true, outcome: outcome} = entry when outcome != :waiting ->
        send(entry.pid, outcome)
        cleanup(state, token, false)

      _ ->
        state
    end
  end

  defp failed(state, token) do
    if entry = state[token], do: failure(entry.id)
    cleanup(state, token)
  end

  defp cleanup(state, token, kill? \\ true) do
    if entry = state[token] do
      Process.cancel_timer(entry.timer)
      Process.demonitor(entry.monitor, [:flush])
      if entry.caller, do: Process.demonitor(entry.caller, [:flush])
      :telemetry.detach(entry.handler)
      if kill?, do: Process.exit(entry.pid, :kill)
    end

    Map.delete(state, token)
  end

  defp failure(id), do: Logger.warning("map_matching.dispatch_failed track_id=#{id}")
end
