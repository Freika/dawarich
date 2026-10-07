defmodule Dawarich.Standalone.SourceRedis do
  @moduledoc false

  @keys ~w(queued scheduled retry dead busy reserved probed processes fetchers heartbeats)a
  @census """
  local function scan_count(pattern, command)
    local cursor = '0'
    local seen = {}
    local count = 0
    repeat
      local page = redis.call('SCAN', cursor, 'MATCH', pattern, 'COUNT', 100)
      cursor = page[1]
      for _, key in ipairs(page[2]) do
        if not seen[key] then
          seen[key] = true
          count = count + redis.call(command, key)
        end
      end
    until cursor == '0'
    return count
  end
  local function live_processes()
    local time = redis.call('TIME')
    local now = tonumber(time[1]) + tonumber(time[2]) / 1000000
    local count = 0
    for _, process in ipairs(redis.call('SMEMBERS', 'processes')) do
      if redis.call('EXISTS', process) == 1 then
        local beat = tonumber(redis.call('HGET', process, 'beat'))
        if not beat or beat ~= beat or math.abs(beat) == math.huge or beat < 0 then
          error('invalid process heartbeat')
        end
        if beat >= now - 60 then
          count = count + 1
        end
      end
    end
    return count
  end
  local function live_fetchers()
    local count = 0
    for _, process in ipairs(redis.call('SMEMBERS', 'limit:processes')) do
      local heartbeat = redis.call('GET', 'limit:heartbeat:' .. process)
      if heartbeat then
        if heartbeat ~= '1' then
          error('invalid fetcher heartbeat')
        end
        count = count + 1
      end
    end
    return count
  end
  return {
    scan_count('queue:*', 'LLEN'),
    redis.call('ZCARD', 'schedule'),
    redis.call('ZCARD', 'retry'),
    redis.call('ZCARD', 'dead'),
    scan_count('*:work', 'HLEN'),
    scan_count('limit_fetch:busy:*', 'LLEN'),
    scan_count('limit_fetch:probed:*', 'LLEN'),
    live_processes(),
    live_fetchers(),
    scan_count('limit:heartbeat:*', 'EXISTS')
  }
  """

  def counts(config) do
    url = Keyword.fetch!(config, :url)
    true = is_binary(url) and url != ""

    opts =
      [database: Keyword.get(config, :database, 1), sync_connect: true] ++
        Dawarich.Redis.socket_options(url)

    {:ok, conn} = Redix.start_link(url, opts)

    try do
      case Redix.command(conn, ["EVAL", @census, "0"]) do
        {:ok, values} when length(values) == length(@keys) ->
          if Enum.all?(values, &(is_integer(&1) and &1 >= 0)),
            do: {:ok, Map.new(Enum.zip(@keys, values))},
            else: {:error, :redis_unreadable}

        _ ->
          {:error, :redis_unreadable}
      end
    after
      if Process.alive?(conn), do: GenServer.stop(conn)
    end
  rescue
    _ -> {:error, :redis_unreadable}
  catch
    _, _ -> {:error, :redis_unreadable}
  end
end
