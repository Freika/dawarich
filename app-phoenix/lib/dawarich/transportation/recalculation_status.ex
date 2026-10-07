defmodule Dawarich.Transportation.RecalculationStatus do
  @moduledoc false
  alias Dawarich.{RailsCache, Redis}
  @ttl 86_400
  @increment """
  local raw = redis.call('GET', KEYS[1])
  local state = raw and cjson.decode(raw) or {processed_tracks = 0, total_tracks = cjson.null}
  if state.status == 'completed' then return state.processed_tracks end
  if redis.call('SADD', KEYS[2], ARGV[1]) == 0 then return state.processed_tracks end
  redis.call('EXPIRE', KEYS[2], 86400)
  state.processed_tracks = state.processed_tracks + 1
  local ttl = 86400
  if type(state.total_tracks) == 'number' and state.processed_tracks >= state.total_tracks then
    state.status = 'completed'
    state.completed_at = ARGV[2]
    ttl = 300
  end
  redis.call('SET', KEYS[1], cjson.encode(state), 'EX', ttl)
  return state.processed_tracks
  """

  def key(user), do: "phoenix:transportation_mode_recalculation:user:#{user}"

  def rails_active?(user),
    do: not Dawarich.Standalone.enabled?() and legacy(user)["status"] == "processing"

  def data(user) do
    native = native_data(user)

    if native && Dawarich.Standalone.enabled?() do
      native
    else
      rails = legacy(user)

      cond do
        is_nil(native) -> rails
        rails["status"] == "processing" -> rails
        rails["status"] in ["completed", "failed"] and newer_rails?(rails, native) -> rails
        true -> native
      end
    end
  end

  defp native_data(user) do
    case Redis.cache_command(["GET", key(user)]) do
      {:ok, nil} -> nil
      {:ok, raw} -> Jason.decode!(raw)
      {:error, reason} -> raise "transportation status unavailable: #{inspect(reason)}"
    end
  end

  defp newer_rails?(rails, native) do
    case {started_at(rails), started_at(native)} do
      {nil, _} -> false
      {_, nil} -> true
      {rails_at, native_at} -> DateTime.compare(rails_at, native_at) != :lt
    end
  end

  defp started_at(%{"started_at" => value}) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _} -> at
      _ -> nil
    end
  end

  defp started_at(_state), do: nil

  def native?(user),
    do: match?({:ok, raw} when is_binary(raw), Redis.cache_command(["GET", key(user)]))

  def in_progress?(user), do: data(user)["status"] == "processing"

  def start(user, total, now) do
    {:ok, _} = Redis.cache_command(["DEL", key(user) <> ":events"])

    state = %{
      "status" => "processing",
      "started_at" => iso(now),
      "total_tracks" => total,
      "processed_tracks" => 0
    }

    put(user, state, @ttl)
    if total == 0, do: complete(user, now), else: :ok
  end

  def complete(user, now),
    do:
      put(
        user,
        Map.merge(data(user), %{"status" => "completed", "completed_at" => iso(now)}),
        300
      )

  def fail(user, now, error_message),
    do:
      put(
        user,
        Map.merge(data(user), %{
          "status" => "failed",
          "error_message" => error_message,
          "completed_at" => iso(now)
        }),
        3_600
      )

  def increment(user, event, now \\ DateTime.utc_now()) do
    {:ok, _} =
      Redis.cache_command([
        "EVAL",
        @increment,
        "2",
        key(user),
        key(user) <> ":events",
        event,
        iso(now)
      ])

    :ok
  end

  def clear(user) do
    {:ok, _} = Redis.cache_command(["DEL", key(user), key(user) <> ":events"])
    :ok
  end

  defp put(user, state, ttl) do
    {:ok, "OK"} =
      Redis.cache_command(["SET", key(user), Jason.encode!(state), "EX", to_string(ttl)])

    :ok
  end

  defp iso(now), do: now |> Map.put(:microsecond, {0, 0}) |> DateTime.to_iso8601()

  defp legacy(user) do
    case RailsCache.get("transportation_mode_recalculation:user:#{user}") do
      {:ok, %{} = state} -> state
      :miss -> %{"status" => "idle"}
      {:error, reason} -> raise "transportation status unavailable: #{inspect(reason)}"
      _ -> %{"status" => "idle"}
    end
  end
end
