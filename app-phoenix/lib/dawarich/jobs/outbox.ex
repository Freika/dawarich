defmodule Dawarich.Jobs.Outbox do
  @moduledoc false

  @writable [:state, :oban_job_id, :dispatched_at, :error_code]

  def writable_columns, do: @writable

  def due?(repo, now) do
    %{num_rows: rows} =
      repo.query!(
        "SELECT 1 FROM public.job_outbox WHERE state = 'pending' AND scheduled_at <= $1 LIMIT 1",
        [now],
        log: false
      )

    rows == 1
  end

  def claim_due(repo, now, limit) do
    repo.query!(
      """
      SELECT event_id, command_type, command_version, payload, aggregate_id
      FROM public.job_outbox
      WHERE state = 'pending' AND scheduled_at <= $1
      ORDER BY scheduled_at, event_id
      LIMIT $2
      FOR UPDATE SKIP LOCKED
      """,
      [now, limit],
      log: false
    ).rows
    |> Enum.map(fn [id, type, version, payload, aggregate_id] ->
      %{
        event_id: Ecto.UUID.cast!(id),
        command_type: type,
        command_version: version,
        payload: payload,
        aggregate_id: aggregate_id
      }
    end)
  end

  def update_delivery!(repo, event_id, attrs) do
    case Keyword.keys(attrs) -- @writable do
      [] -> :ok
      other -> raise ArgumentError, "Phoenix may not write job_outbox columns #{inspect(other)}"
    end

    {sets, values} =
      attrs
      |> Enum.with_index(2)
      |> Enum.map(fn {{column, value}, index} -> {"#{column} = $#{index}", value} end)
      |> Enum.unzip()

    repo.query!(
      "UPDATE public.job_outbox SET #{Enum.join(sets, ", ")} WHERE event_id = $1",
      [Ecto.UUID.dump!(event_id) | values],
      log: false
    )

    :ok
  end

  def prune!(repo, before, limit \\ 1_000) do
    %{num_rows: deleted} =
      repo.query!(
        """
        WITH batch AS MATERIALIZED (
          SELECT event_id FROM public.job_outbox
          WHERE state = 'dispatched' AND dispatched_at < $1
          LIMIT $2)
        DELETE FROM public.job_outbox USING batch WHERE job_outbox.event_id = batch.event_id
        """,
        [before, limit],
        log: false
      )

    deleted
  end
end
