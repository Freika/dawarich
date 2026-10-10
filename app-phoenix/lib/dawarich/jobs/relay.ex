defmodule Dawarich.Jobs.Relay do
  @moduledoc false
  use GenServer
  require Logger

  alias Dawarich.Jobs.{Dispatch, Housekeeping, Registry}

  @interval 1_000
  @max_backoff 60_000
  @beat_every_ms 10_000
  @housekeeping_every_ms 3_600_000
  @stale_seconds 60

  def start_link(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  def tick(server \\ __MODULE__), do: GenServer.call(server, :tick, 30_000)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    oban = Keyword.get(opts, :oban, Oban)

    state = %{
      node: Keyword.fetch!(opts, :node),
      repo: Keyword.get_lazy(opts, :repo, fn -> Oban.config(oban).repo end),
      oban: oban,
      commands: Keyword.get(opts, :commands, &Registry.command/1),
      started_at: DateTime.utc_now(),
      beat_at: nil,
      housekept_at: nil,
      backoff: @interval,
      errors: 0
    }

    if Keyword.get(opts, :auto, true), do: Process.send_after(self(), :tick, 0)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    state = run(state)
    Process.send_after(self(), :tick, state.backoff)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_call(:tick, _from, state) do
    state = run(state)
    {:reply, state, state}
  end

  @impl true
  def terminate(_reason, state) do
    state.repo.query!(
      "DELETE FROM phoenix.runtime_nodes WHERE node = $1 AND started_at = $2",
      [state.node, state.started_at],
      log: false
    )
  catch
    _kind, _reason -> :ok
  end

  defp run(state) do
    now = DateTime.utc_now()

    state =
      case guarded(fn -> dispatch(beat(state, now), now) end) do
        {:ok, state} -> %{state | backoff: @interval}
        {:error, class} -> failed(state, class)
      end

    housekeep(state, now)
  end

  defp dispatch(state, now) do
    Dispatch.run(repo: state.repo, oban: state.oban, commands: state.commands, now: now)
    state
  end

  defp guarded(fun) do
    {:ok, fun.()}
  rescue
    exception -> {:error, inspect(exception.__struct__)}
  catch
    kind, _reason -> {:error, inspect(kind)}
  end

  defp failed(state, class) do
    backoff = min(state.backoff * 2, @max_backoff)
    Logger.warning("[jobs.relay] tick failed (#{class}); next attempt in #{backoff} ms")
    %{state | backoff: backoff, errors: state.errors + 1}
  end

  defp beat(%{beat_at: last} = state, now) do
    if last && DateTime.diff(now, last, :millisecond) < @beat_every_ms do
      state
    else
      %{num_rows: rows} =
        state.repo.query!(
          """
          INSERT INTO phoenix.runtime_nodes AS n (node, started_at, beat_at) VALUES ($1, $2, $3)
          ON CONFLICT (node) DO UPDATE SET started_at = EXCLUDED.started_at, beat_at = EXCLUDED.beat_at
          WHERE n.started_at = EXCLUDED.started_at OR n.beat_at < $4
          """,
          [state.node, state.started_at, now, DateTime.add(now, -@stale_seconds)],
          log: false
        )

      if rows == 0 do
        Logger.error(
          "[jobs.relay] two live BEAMs share the Oban node #{state.node} (or the previous one stopped " <>
            "less than #{@stale_seconds} s ago); give each web container its own HOSTNAME"
        )
      end

      Dawarich.Metrics.Imports.collect(state.repo)
      %{state | beat_at: now}
    end
  end

  defp housekeep(%{housekept_at: last} = state, now) do
    if last && DateTime.diff(now, last, :millisecond) < @housekeeping_every_ms do
      state
    else
      with {:error, class} <- guarded(fn -> Housekeeping.run!(state.repo, now) end) do
        Logger.warning("[jobs.relay] housekeeping failed (#{class}); next attempt in 1 h")
      end

      %{state | housekept_at: now}
    end
  end
end
