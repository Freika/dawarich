defmodule Dawarich.Geocoding.RateLimiter do
  @moduledoc false
  use GenServer

  require Logger

  alias Dawarich.Geocoding.Providers
  alias Dawarich.Redis

  @prefix "geocoding:rate_limit:"
  @lua ~S"""
  local clock = redis.call('TIME')
  local now = tonumber(clock[1]) * 1000000 + tonumber(clock[2])
  local slot = tonumber(redis.call('GET', KEYS[1]) or '0')
  if slot < now then slot = now end
  local wait = slot - now
  local max_wait = tonumber(ARGV[2])
  if max_wait >= 0 and wait > max_wait then return -1 end
  local next_slot = slot + tonumber(ARGV[1])
  redis.call('SET', KEYS[1], string.format('%.0f', next_slot), 'PX', string.format('%.0f', math.floor((next_slot - now) / 1000) + 1000))
  return wait
  """

  def lua, do: @lua

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(slots), do: {:ok, slots}

  @impl true
  def handle_call({:reserve, key, interval, max_wait}, _from, slots) do
    now = System.monotonic_time(:microsecond)
    initial = if is_nil(max_wait), do: now + interval, else: now
    slot = max(Map.get(slots, key, initial), now)
    wait = slot - now

    if not is_nil(max_wait) and wait > max_wait,
      do: {:reply, nil, slots},
      else: {:reply, wait, Map.put(slots, key, slot + interval)}
  end

  def local_throttle(config, fun, max_wait \\ nil) do
    Logger.warning("event=geocoding.rate_limiter_unavailable pacing=local")
    interval = round(1_000_000 / config.rps)

    case GenServer.call(__MODULE__, {:reserve, key(config), interval, max_wait}) do
      nil ->
        nil

      wait ->
        if wait > 0, do: Process.sleep(div(wait + 999, 1000))
        fun.()
    end
  end

  def throttle(%{rps: rps}, fun) when is_nil(rps) or rps <= 0, do: fun.()

  def throttle(config, fun) do
    interval = round(1_000_000 / config.rps)

    case Redis.command([
           "EVAL",
           @lua,
           "1",
           @prefix <> key(config),
           Integer.to_string(interval),
           "-1"
         ]) do
      {:ok, wait} when is_integer(wait) and wait >= 0 ->
        if wait > 0, do: Process.sleep(div(wait + 999, 1000))
        fun.()

      {:error, _reason} ->
        local_throttle(config, fun)
    end
  end

  def key(config),
    do:
      [
        Atom.to_string(config.provider),
        Providers.bare_host(config.host),
        Providers.key_digest(config)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(":")
end
