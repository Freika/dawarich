defmodule Dawarich.Geocoding.RateLimiter do
  @moduledoc false

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

      {:error, reason} ->
        Logger.warning("event=geocoding.rate_limiter_unavailable reason=#{inspect(reason)}")
        Process.sleep(div(interval + 999, 1000))
    end

    fun.()
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
