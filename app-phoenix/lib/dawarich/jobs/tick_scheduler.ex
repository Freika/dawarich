defmodule Dawarich.Jobs.TickScheduler do
  @moduledoc false
  use GenServer
  @behaviour Oban.Plugin

  alias Dawarich.Jobs.Registry
  alias Oban.Cron.Expression

  @impl Oban.Plugin
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, Map.new(opts), name: name)
  end

  @impl Oban.Plugin
  def validate(opts), do: Oban.Cron.validate(Keyword.delete(opts, :now))

  @impl Oban.Plugin
  def format_logger_output(_conf, %{jobs: jobs}), do: %{jobs: Enum.map(jobs, & &1.id)}

  @impl GenServer
  def init(state) do
    Process.flag(:trap_exit, true)
    handler = {__MODULE__, state.conf.name}
    :telemetry.detach(handler)

    :ok =
      :telemetry.attach(
        handler,
        [:oban, :peer, :election, :stop],
        &__MODULE__.leadership_changed/4,
        {self(), state.conf.name}
      )

    send(self(), :evaluate)
    {:ok, state |> Map.put(:timer, nil) |> Map.put(:handler, handler)}
  end

  def leadership_changed(
        _event,
        _measurements,
        %{conf: %{name: name}, leader: true, was_leader: false},
        {pid, name}
      ),
      do: send(pid, :evaluate)

  def leadership_changed(_event, _measurements, _metadata, _config), do: :ok

  @impl GenServer
  def handle_info(:evaluate, state) do
    if Oban.Peer.leader?(state.conf) do
      now = Map.get(state, :now, &DateTime.utc_now/0).()
      evaluate(state.conf, state.crontab, Map.get(state, :timezone, "Etc/UTC"), now)
    end

    if state.timer, do: Process.cancel_timer(state.timer)
    timer = Process.send_after(self(), :evaluate, Oban.Cron.interval_to_next_minute() + 1_000)
    {:noreply, %{state | timer: timer}}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    :telemetry.detach(state.handler)
    :ok
  end

  def evaluate(conf, crontab, timezone, now) do
    conf.repo.transaction(fn ->
      Enum.flat_map(crontab, fn entry ->
        {expression, worker, opts} = normalize(entry)
        zone = Keyword.get(opts, :timezone, timezone)
        key = key(worker)

        [[last]] =
          conf.repo.query!(
            "SELECT max(tick) FROM phoenix.cron_ticks WHERE key=$1",
            [key],
            log: false
          ).rows

        case due(expression, zone, now) do
          nil ->
            []

          tick ->
            if is_nil(last) or NaiveDateTime.compare(DateTime.to_naive(tick), last) == :gt do
              admit(conf, key, tick, expression, worker, opts, zone)
            else
              []
            end
        end
      end)
    end)
  end

  defp due(expression, zone, now) do
    parsed = Expression.parse!(expression)
    second = DateTime.to_unix(now)

    latest =
      div(second - if(now.second == 0 and elem(now.microsecond, 0) == 0, do: 1, else: 0), 60) * 60

    Enum.find_value([latest, latest - 60], fn slot ->
      tick = DateTime.from_unix!(slot)

      if second - slot <= 60 and Expression.now?(parsed, DateTime.shift_zone!(tick, zone)),
        do: tick
    end)
  end

  defp admit(conf, key, tick, expression, worker, opts, zone) do
    result =
      conf.repo.query!(
        "INSERT INTO phoenix.cron_ticks(key,tick) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING tick",
        [key, tick],
        log: false
      )

    if result.num_rows == 1 do
      {args, opts} = opts |> Keyword.delete(:timezone) |> Keyword.pop(:args, %{})

      meta = %{
        "cron" => true,
        "cron_expr" => expression,
        "cron_tz" => zone,
        "cron_tick" => DateTime.to_unix(tick),
        "cron_name" => key
      }

      opts = Keyword.update(opts, :meta, meta, &Map.merge(&1, meta))
      [Oban.insert!(conf.name, worker.new(args, opts))]
    else
      []
    end
  end

  defp normalize({expression, worker}), do: {expression, worker, []}
  defp normalize({expression, worker, opts}), do: {expression, worker, opts}

  defp key(worker) do
    case Enum.find(Registry.entries(), &(&1.kind == :cron and &1.worker == worker)) do
      nil -> "native:" <> Oban.Worker.to_string(worker)
      entry -> entry.key
    end
  end
end
