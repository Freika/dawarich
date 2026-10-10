defmodule Dawarich.Uploads.SweepWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 26,
    unique: [period: :infinity, states: [:available, :scheduled, :retryable]]

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run()

  def run(opts \\ []) do
    repo = Keyword.get_lazy(opts, :repo, &Dawarich.Jobs.repo/0)

    repo.transaction(fn ->
      rows =
        repo.query!(
          "SELECT reference,user_id FROM phoenix.native_uploads WHERE state='pending' AND expires_at<=timezone('UTC',now()) ORDER BY expires_at LIMIT 100 FOR UPDATE SKIP LOCKED",
          [], log: false).rows

      for [ref, owner] <- rows do
        row = Dawarich.Uploads.Records.read(repo, ref, owner)

        if Dawarich.Uploads.Records.attached?(repo, row.blob_id),
          do: Dawarich.Uploads.Records.finish!(repo, row, "claimed"),
          else: Dawarich.Uploads.Records.cancel!(repo, row, "expired")
      end

      [[next]] =
        repo.query!(
          "SELECT min(expires_at) FROM phoenix.native_uploads WHERE state='pending'",
          [], log: false).rows

      if next do
        at =
          if NaiveDateTime.compare(next, NaiveDateTime.utc_now()) == :gt,
            do: next,
            else: NaiveDateTime.add(NaiveDateTime.utc_now(), 1)

        repo.insert!(__MODULE__.new(%{}, scheduled_at: DateTime.from_naive!(at, "Etc/UTC")),
          prefix: "oban"
        )
      end

      length(rows)
    end)
  end
end
