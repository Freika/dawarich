defmodule Dawarich.ReleaseOperations.PlaceNameLocks do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 10

  alias Dawarich.ReleaseOperations
  alias Dawarich.ReleaseOperations.PlaceNames

  @batch 1_000
  @page """
  SELECT id, name, geodata FROM places
  WHERE name_locked_at IS NULL AND name <> 'Suggested place' AND id > $1
  ORDER BY id LIMIT $2
  """
  @lock "UPDATE places SET name_locked_at = now() WHERE id = ANY($1) AND name_locked_at IS NULL"

  defdelegate args_from_command(version, payload), to: ReleaseOperations, as: :no_payload

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"version" => 1}}), do: run(Dawarich.Jobs.repo())
  def perform(_job), do: {:cancel, :unsupported_version}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  def run(repo, after_id \\ 0) do
    case repo.query!(@page, [after_id, @batch], log: false).rows do
      [] ->
        :ok

      rows ->
        ids =
          for [id, name, geodata] <- rows, not PlaceNames.machine_named?(name, geodata), do: id

        if ids != [], do: repo.query!(@lock, [ids], log: false)
        run(repo, rows |> List.last() |> hd())
    end
  end
end
