defmodule Dawarich.Cable.PgStore do
  @moduledoc false

  def append(repo, namespace, channel, payload) do
    if repo.in_transaction?() do
      {:ok, append_in_transaction(repo, namespace, channel, payload)}
    else
      repo.transaction(fn -> append_in_transaction(repo, namespace, channel, payload) end)
    end
  end

  def snapshot(repo, namespace, cursor, clock \\ nil) do
    sql = """
    WITH batch AS MATERIALIZED (
      SELECT seq, channel, payload FROM phoenix.cable_events
      WHERE namespace = $1 AND seq > $2 ORDER BY seq LIMIT 100
    ), observed AS (
      UPDATE phoenix.cable_events e
      SET observed_at = COALESCE($3::timestamptz, statement_timestamp())
      FROM batch b WHERE e.namespace = $1 AND e.seq = b.seq AND e.observed_at IS NULL
      RETURNING e.seq
    )
    SELECT COALESCE(s.last_seq, 0), COALESCE(s.retired_through, 0), e.seq, e.channel, e.payload
    FROM (SELECT 1) AS anchor
    LEFT JOIN phoenix.cable_streams s ON s.namespace = $1
    LEFT JOIN batch e ON true
    ORDER BY e.seq
    """

    case repo.query(sql, [namespace, cursor, clock], log: false) do
      {:ok, %{rows: [[last_seq, retired_through | _] | _] = rows}} ->
        events =
          for [_, _, seq, channel, payload] <- rows, not is_nil(seq), do: [seq, channel, payload]

        {:ok, %{last_seq: last_seq, retired_through: retired_through, events: events}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def head(repo, namespace) do
    case repo.query(
           "SELECT last_seq FROM phoenix.cable_streams WHERE namespace = $1",
           [namespace],
           log: false
         ) do
      {:ok, %{rows: [[seq]]}} -> {:ok, seq}
      {:ok, %{rows: []}} -> {:ok, 0}
      {:error, reason} -> {:error, reason}
    end
  end

  defp append_in_transaction(repo, namespace, channel, payload) do
    repo.query!(
      "INSERT INTO phoenix.cable_streams(namespace) VALUES ($1) ON CONFLICT DO NOTHING",
      [namespace],
      log: false
    )

    %{rows: [[seq]]} =
      repo.query!(
        "UPDATE phoenix.cable_streams SET last_seq = last_seq + 1 WHERE namespace = $1 RETURNING last_seq",
        [namespace],
        log: false
      )

    repo.query!(
      "INSERT INTO phoenix.cable_events(namespace, seq, channel, payload, created_at) VALUES ($1, $2, $3, $4, statement_timestamp())",
      [namespace, seq, channel, payload],
      log: false
    )

    seq
  end
end
