defmodule Dawarich.Subscriptions.Cache do
  @moduledoc false
  alias Dawarich.{RailsCache.Wire, Redis}
  @ttl 604_800

  def claim(event, context) do
    bytes = Wire.encode_boolean(true, expires_at: now(context) + @ttl)

    command(["SET", processed(event), bytes, "NX", "EX", Integer.to_string(@ttl)], context) ==
      {:ok, "OK"}
  end

  def release(event, context), do: command(["DEL", processed(event)], context)
  def processed(event), do: "manager_callback:processed:" <> to_string(event)
  def watermark(id), do: "manager_callback:last_seen_ms:" <> to_string(id)

  def older?(claims, context) do
    stamp = stamp(claims)
    stamp != 0 and stamp < read(claims["user_id"], context)
  end

  def advance(claims, context) do
    stamp = stamp(claims)

    if stamp != 0 and stamp >= read(claims["user_id"], context) do
      bytes = entry(stamp, now(context) + @ttl)

      command(
        ["SET", watermark(claims["user_id"]), bytes, "EX", Integer.to_string(@ttl)],
        context
      )
    end
  end

  def invalidate(key, context) do
    Dawarich.TtlCache.delete({DawarichWeb.RateLimit, key})
    command(["DEL", "rack_attack/plan/" <> (key || "")], context)
  end

  defp stamp(claims) do
    case claims["event_timestamp_ms"] do
      n when is_integer(n) ->
        n

      value when is_binary(value) ->
        case Integer.parse(value) do
          {n, _} -> n
          _ -> 0
        end

      _ ->
        0
    end
  end

  defp read(id, context) do
    with {:ok, bytes} when is_binary(bytes) <- command(["GET", watermark(id)], context),
         {:ok, %{value: value, expires_at: expiry}} when is_integer(value) <- Wire.decode(bytes),
         true <- is_nil(expiry) or expiry > now(context),
         do: value,
         else: (_ -> 0)
  end

  def entry(value, expires) when value >= 0 do
    encoded =
      cond do
        value == 0 ->
          <<?i, 0>>

        value <= 122 ->
          <<?i, value + 5>>

        value <= 2_147_483_647 ->
          bytes = :binary.encode_unsigned(value, :little)
          <<?i, byte_size(bytes), bytes::binary>>

        true ->
          bytes = :binary.encode_unsigned(value, :little)
          size = div(byte_size(bytes) + 1, 2) * 2
          <<?l, ?+, div(size, 2) + 5, bytes::binary, 0::size((size - byte_size(bytes)) * 8)>>
      end

    <<0, 17, 1, expires * 1.0::little-float-64, -1::little-signed-32, 4, 8, encoded::binary>>
  end

  defp command(args, context), do: Map.get(context, :cache_command, &Redis.cache_command/1).(args)
  defp now(context), do: Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_unix()
end
