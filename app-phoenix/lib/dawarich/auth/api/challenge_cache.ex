defmodule Dawarich.Auth.Api.ChallengeCache do
  @moduledoc false
  alias Dawarich.{RailsCache.Wire, Redis}

  def exists?(jti, context) do
    case command(["GET", key(jti)], context) do
      {:ok, nil} ->
        {:ok, false}

      {:ok, bytes} ->
        case Wire.decode(bytes) do
          {:ok, %{expires_at: expires}} when is_nil(expires) -> {:ok, true}
          {:ok, %{expires_at: expires}} when is_number(expires) -> {:ok, expires > epoch(context)}
          _ -> {:replay, :cache_entry}
        end

      _ ->
        {:replay, :cache_read}
    end
  end

  def mark(jti, context) do
    bytes = Wire.encode_boolean(true, expires_at: epoch(context) + 300)

    case command(["SET", key(jti), bytes, "NX", "PX", "300000"], context) do
      {:ok, "OK"} -> true
      {:ok, nil} -> false
      _ -> nil
    end
  end

  defp epoch(context),
    do:
      DateTime.to_unix(Map.get(context, :clock, &DateTime.utc_now/0).(), :microsecond) / 1_000_000

  defp key(jti), do: "otp_challenge:consumed:" <> jti
  defp command(args, context), do: Map.get(context, :cache_command, &Redis.cache_command/1).(args)
end
