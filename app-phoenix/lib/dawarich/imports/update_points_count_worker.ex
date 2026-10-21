defmodule Dawarich.Imports.UpdatePointsCountWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 3,
    unique: [keys: [:import_id], states: [:available, :scheduled, :retryable], period: :infinity]

  def args_from_command(1, %{"import_id" => id} = payload)
      when is_integer(id) and map_size(payload) == 1,
      do: {:ok, %{"import_id" => id}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(1)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"import_id" => id}}) do
    Dawarich.Jobs.repo().query!(
      """
      UPDATE imports SET processed = c.n, updated_at = now() AT TIME ZONE 'UTC'
      FROM (SELECT count(*)::integer AS n FROM points WHERE import_id = $1) AS c
      WHERE imports.id = $1 AND imports.processed IS DISTINCT FROM c.n
      """,
      [id],
      log: false
    )

    :ok
  end
end
