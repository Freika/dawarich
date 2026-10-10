defmodule Dawarich.Uploads.SweepSchedule do
  @moduledoc false
  alias Dawarich.Uploads.SweepWorker

  def enqueue!(repo, deadline) do
    unless repo.in_transaction?(),
      do: raise(ArgumentError, "Sweep scheduling requires a transaction")

    repo.query!(
      "SELECT pg_advisory_xact_lock(hashtextextended('native-upload-sweep',0))",
      [],
      log: false
    )

    outstanding =
      repo.query!(
        "SELECT id,scheduled_at FROM oban.oban_jobs WHERE worker='Dawarich.Uploads.SweepWorker' AND state IN ('available','scheduled','retryable') ORDER BY scheduled_at,id FOR UPDATE",
        [],
        log: false
      ).rows

    case {deadline, outstanding} do
      {nil, rows} ->
        cancel!(repo, Enum.map(rows, &hd/1))

      {at, []} ->
        repo.insert!(SweepWorker.new(%{}, scheduled_at: datetime(at)), prefix: "oban")

      {at, [[id, current] | extra]} ->
        at = DateTime.to_naive(datetime(at))
        next = if NaiveDateTime.compare(at, current) == :lt, do: at, else: current

        repo.query!("UPDATE oban.oban_jobs SET scheduled_at=$2 WHERE id=$1", [id, next],
          log: false
        )

        cancel!(repo, Enum.map(extra, &hd/1))
    end

    :ok
  end

  defp cancel!(repo, ids),
    do:
      repo.query!(
        "UPDATE oban.oban_jobs SET state='cancelled',cancelled_at=now() WHERE id=ANY($1)",
        [ids], log: false)

  defp datetime(%DateTime{} = at), do: at
  defp datetime(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
end
