defmodule Dawarich.Cable.PgStore do
  @moduledoc false

  def append(repo, namespace, channel, payload) do
    if repo.in_transaction?() do
      {:ok, append_in_transaction(repo, namespace, channel, payload)}
    else
      repo.transaction(fn -> append_in_transaction(repo, namespace, channel, payload) end)
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
