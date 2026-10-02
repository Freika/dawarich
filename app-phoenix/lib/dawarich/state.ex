defmodule Dawarich.State do
  @moduledoc false

  @claim """
  INSERT INTO phoenix.once_claims AS c (key, expires_at)
  VALUES ($1, statement_timestamp() + make_interval(secs => $2))
  ON CONFLICT (key) DO UPDATE SET expires_at = EXCLUDED.expires_at
  WHERE c.expires_at <= statement_timestamp()
  """
  @claimed "SELECT 1 FROM phoenix.once_claims WHERE key = $1 AND expires_at > statement_timestamp()"
  @unclaim "DELETE FROM phoenix.once_claims WHERE key = $1"
  @increment """
  INSERT INTO phoenix.counters AS c (key, value, expires_at)
  VALUES ($1, $2, statement_timestamp() + make_interval(secs => $3))
  ON CONFLICT (key) DO UPDATE SET
    value = CASE WHEN c.expires_at <= statement_timestamp() THEN EXCLUDED.value ELSE c.value + EXCLUDED.value END,
    expires_at = CASE WHEN c.expires_at <= statement_timestamp() THEN EXCLUDED.expires_at ELSE c.expires_at END
  RETURNING value
  """
  @count "SELECT value FROM phoenix.counters WHERE key = $1 AND expires_at > statement_timestamp()"

  def claim(repo, key, ttl_seconds)
      when is_binary(key) and is_integer(ttl_seconds) and ttl_seconds > 0,
      do: repo.query!(@claim, [key, ttl_seconds], log: false).num_rows == 1

  def claimed?(repo, key) when is_binary(key),
    do: repo.query!(@claimed, [key], log: false).num_rows == 1

  def unclaim(repo, key) when is_binary(key) do
    repo.query!(@unclaim, [key], log: false)
    :ok
  end

  def increment(repo, key, by, ttl_seconds)
      when is_binary(key) and is_integer(by) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    %{rows: [[value]]} = repo.query!(@increment, [key, by, ttl_seconds], log: false)
    value
  end

  def count(repo, key) when is_binary(key) do
    case repo.query!(@count, [key], log: false).rows do
      [[value]] -> value
      [] -> 0
    end
  end
end
