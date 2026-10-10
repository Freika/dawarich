defmodule Dawarich.Imports.StaleRecovery do
  @moduledoc false
  require Logger
  alias Dawarich.Jobs.Ownership
  alias Dawarich.State.Lease
  alias DawarichWeb.Translate
  @key "cron:stale_jobs_recovery_job"
  @prefix "jobs.stale_jobs_recovery_job."

  def run(repo, now \\ NaiveDateTime.utc_now()) do
    case Ownership.with_owner(repo, @key, :oban, fn -> stamp(repo) end) do
      {:ok, stamp} ->
        scan(repo, "exports", NaiveDateTime.add(now, -7200), now, stamp, 0)
        scan(repo, "imports", NaiveDateTime.add(now, -21_600), now, stamp, 0)
        :ok

      {:skip, _} ->
        :ok
    end
  end

  defp scan(repo, table, cutoff, now, stamp, cursor) do
    rows =
      repo.query!(
        "SELECT id FROM #{table} WHERE id>$1 AND status=1 AND processing_started_at<$2 ORDER BY id LIMIT 1000",
        [cursor, cutoff],
        log: false
      ).rows

    Enum.each(rows, fn [id] ->
      try do
        Ownership.with_owner(repo, @key, :oban, fn ->
          if stamp(repo) == stamp, do: recover(repo, table, id, cutoff, now)
        end)
      rescue
        _ -> Logger.error("Failed to recover stale #{table} row #{id}")
      end
    end)

    if length(rows) == 1000,
      do: scan(repo, table, cutoff, now, stamp, rows |> List.last() |> hd())
  end

  defp recover(repo, "imports" = table, id, cutoff, now) do
    holder = Ecto.UUID.generate()
    name = "import:#{id}"

    if Lease.acquire(repo, name, holder, 60_000) do
      try do
        unless active_import?(repo, id), do: fail(repo, table, id, cutoff, now)
      after
        Lease.release(repo, name, holder)
      end
    end
  end

  defp recover(repo, "exports" = table, id, cutoff, now),
    do: fail(repo, table, id, cutoff, now)

  defp active_import?(repo, id) do
    repo.query!(
      """
      SELECT 1 FROM phoenix.import_runs r JOIN oban.oban_jobs j ON j.id=r.job_id
      WHERE r.import_id=$1 AND j.state='executing' AND j.attempt=r.attempt
        AND j.args->>'event_id'=r.event_id::text
        AND j.args->>'import_id'=r.import_id::text AND j.args->>'user_id'=r.user_id::text
        AND j.attempted_at>statement_timestamp()-interval '55 minutes'
      LIMIT 1
      """,
      [id],
      log: false
    ).rows != []
  end

  defp fail(repo, table, id, cutoff, now) do
    case repo.query!(
           "SELECT i.user_id,i.name,u.settings FROM #{table} i JOIN users u ON u.id=i.user_id WHERE i.id=$1 AND i.status=1 AND i.processing_started_at<$2 FOR UPDATE OF i",
           [id, cutoff],
           log: false
         ).rows do
      [[user, name, settings]] ->
        entity = if table == "imports", do: "import", else: "export"
        locale = Dawarich.Mail.ExploreFeatures.locale(settings, nil)

        error =
          Translate.t(
            locale,
            @prefix <> entity <> "_timed_out_after_being_stuck_in_processing",
            %{}
          )

        changed =
          repo.query!(
            "UPDATE #{table} SET status=3,error_message=$2,updated_at=$3 WHERE id=$1 AND status=1 AND processing_started_at<$4 RETURNING id",
            [id, error, now, cutoff],
            log: false
          ).rows

        if changed != [] do
          title = Translate.t(locale, @prefix <> entity <> "_failed", %{})

          content =
            Translate.t(
              locale,
              @prefix <> entity <> "_name_was_stuck_in_processing_and_has_been_marked",
              %{name: name}
            )

          Dawarich.Notifications.create!(repo, user, :error, title, content, now)
        end

      [] ->
        :ok
    end
  end

  defp stamp(repo) do
    [[stamp]] =
      repo.query!("SELECT updated_at FROM phoenix.job_owners WHERE key=$1", [@key], log: false).rows

    stamp
  end
end
