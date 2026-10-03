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
  @claim_all """
  INSERT INTO phoenix.once_claims AS c (key, expires_at)
  SELECT k, statement_timestamp() + make_interval(secs => $2) FROM unnest($1::text[]) AS k ORDER BY k
  ON CONFLICT (key) DO UPDATE SET expires_at = EXCLUDED.expires_at
  WHERE c.expires_at <= statement_timestamp()
  RETURNING key
  """
  @unclaim_all "DELETE FROM phoenix.once_claims WHERE key = ANY($1::text[])"
  @slide """
  UPDATE phoenix.once_claims SET expires_at = statement_timestamp() + make_interval(secs => $2)
  WHERE key = $1 AND expires_at > statement_timestamp()
  """
  @increment """
  INSERT INTO phoenix.counters AS c (key, value, expires_at)
  VALUES ($1, $2, statement_timestamp() + make_interval(secs => $3))
  ON CONFLICT (key) DO UPDATE SET
    value = CASE WHEN c.expires_at <= statement_timestamp() THEN EXCLUDED.value ELSE c.value + EXCLUDED.value END,
    expires_at = CASE WHEN c.expires_at <= statement_timestamp() THEN EXCLUDED.expires_at ELSE c.expires_at END
  RETURNING value
  """
  @count "SELECT value FROM phoenix.counters WHERE key = $1 AND expires_at > statement_timestamp()"
  @tokens "SELECT key, token FROM phoenix.epochs WHERE key = ANY($1::text[])"
  @seed """
  INSERT INTO phoenix.epochs (key, token)
  SELECT * FROM unnest($1::text[], $2::text[])
  ON CONFLICT (key) DO NOTHING
  """
  @bump """
  INSERT INTO phoenix.epochs AS e (key, token)
  SELECT * FROM unnest($1::text[], $2::text[])
  ON CONFLICT (key) DO UPDATE SET token = EXCLUDED.token, updated_at = statement_timestamp()
  """
  @registration "SELECT enabled FROM phoenix.registration_setting"
  @put_registration """
  INSERT INTO phoenix.registration_setting (id, enabled, updated_at)
  VALUES (true, $1, statement_timestamp())
  ON CONFLICT (id) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = EXCLUDED.updated_at
  """
  @cursor "SELECT value FROM phoenix.cursors WHERE key = $1"
  @put_cursor """
  INSERT INTO phoenix.cursors (key, value, updated_at) VALUES ($1, $2, statement_timestamp())
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at
  """
  @delete_cursor "DELETE FROM phoenix.cursors WHERE key = $1"
  @increment_cursor """
  INSERT INTO phoenix.cursors AS c (key, value, updated_at) VALUES ($1, '1', statement_timestamp())
  ON CONFLICT (key) DO UPDATE SET value = (c.value::bigint + 1)::text, updated_at = EXCLUDED.updated_at
  RETURNING value::bigint
  """

  def claim(repo, key, ttl_seconds)
      when is_binary(key) and is_integer(ttl_seconds) and ttl_seconds > 0,
      do: repo.query!(@claim, [key, ttl_seconds], log: false).num_rows == 1

  def claimed?(repo, key) when is_binary(key),
    do: repo.query!(@claimed, [key], log: false).num_rows == 1

  def unclaim(repo, key) when is_binary(key) do
    repo.query!(@unclaim, [key], log: false)
    :ok
  end

  def claim_all(repo, keys, ttl_seconds)
      when is_list(keys) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    case Enum.uniq(keys) do
      [] -> []
      keys -> List.flatten(repo.query!(@claim_all, [keys, ttl_seconds], log: false).rows)
    end
  end

  def unclaim_all(repo, keys) when is_list(keys) do
    repo.query!(@unclaim_all, [keys], log: false)
    :ok
  end

  def debounce(repo, key, ttl_seconds),
    do: claim(repo, key, ttl_seconds) or slide(repo, key, ttl_seconds)

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

  def epoch_tokens(repo, keys) when is_list(keys) do
    found = tokens(repo, keys)

    case keys |> Enum.reject(&Map.has_key?(found, &1)) |> lock_order() do
      [] ->
        found

      missing ->
        repo.query!(@seed, [missing, Enum.map(missing, fn _ -> token() end)], log: false)
        tokens(repo, keys)
    end
  end

  def bump_epochs(repo, keys) when is_list(keys) do
    keys = lock_order(keys)
    repo.query!(@bump, [keys, Enum.map(keys, fn _ -> token() end)], log: false)
    :ok
  end

  def registration_enabled(repo, default) when is_boolean(default) do
    case repo.query!(@registration, [], log: false).rows do
      [[enabled]] -> enabled
      [] -> default
    end
  end

  def put_registration_enabled(repo, enabled) when is_boolean(enabled) do
    repo.query!(@put_registration, [enabled], log: false)
    :ok
  end

  def cursor(repo, key) when is_binary(key) do
    case repo.query!(@cursor, [key], log: false).rows do
      [[value]] -> value
      [] -> nil
    end
  end

  def put_cursor(repo, key, value) when is_binary(key) and is_binary(value) do
    repo.query!(@put_cursor, [key, value], log: false)
    :ok
  end

  def delete_cursor(repo, key) when is_binary(key) do
    repo.query!(@delete_cursor, [key], log: false)
    :ok
  end

  def increment_cursor(repo, key) when is_binary(key) do
    %{rows: [[value]]} = repo.query!(@increment_cursor, [key], log: false)
    value
  end

  defp slide(repo, key, ttl_seconds) do
    repo.query!(@slide, [key, ttl_seconds], log: false)
    false
  end

  defp tokens(repo, keys),
    do:
      Map.new(repo.query!(@tokens, [keys], log: false).rows, fn [key, token] -> {key, token} end)

  defp lock_order(keys), do: keys |> Enum.uniq() |> Enum.sort()

  defp token, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
end
