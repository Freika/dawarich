defmodule Dawarich.Cable.Delivery do
  @moduledoc false
  @context {__MODULE__, :intent}
  @publish """
  if redis.call('EXISTS', KEYS[1]) == 1 then return 0 end
  redis.call('SET', KEYS[1], '1')
  local delivered = redis.pcall('PUBLISH', ARGV[1], ARGV[2])
  if type(delivered) == 'table' and delivered.err then
    redis.call('DEL', KEYS[1])
    return redis.error_reply(delivered.err)
  end
  return delivered
  """

  def with_intent(intent, fun) do
    previous = Process.get(@context)
    Process.put(@context, {intent, %{}})

    try do
      fun.()
    after
      if previous, do: Process.put(@context, previous), else: Process.delete(@context)
    end
  end

  def publish(channel, payload, publisher) do
    case Process.get(@context) do
      {intent, counts} ->
        index = Map.get(counts, channel, 0)
        Process.put(@context, {intent, Map.put(counts, channel, index + 1)})

        digest =
          Base.encode16(:crypto.hash(:sha256, "#{intent}/#{channel}/#{index}"), case: :lower)

        Dawarich.Redis.command(
          ["EVAL", @publish, "1", "cable:delivered:" <> digest, channel, payload],
          publisher
        )

      nil ->
        Dawarich.Redis.command(["PUBLISH", channel, payload], publisher)
    end
  end
end
