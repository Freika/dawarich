defmodule Dawarich.A12f3bG04Test do
  use Dawarich.JobsCase

  alias Dawarich.Digests.Scheduling
  alias Dawarich.Jobs.{Ownership, Registry}
  alias Dawarich.Lite.ArchivalWarningWorker
  alias Dawarich.RawData.{ArchiveWorker, ClearWorker}

  @oban __MODULE__.Oban
  @now ~U[2026-03-29 01:30:00Z]

  defmodule RollbackRepo do
    def transaction(fun),
      do:
        Dawarich.ScratchRepo.transaction(fn ->
          fun.()
          Dawarich.ScratchRepo.rollback(:mail_insert_failed)
        end)

    def query!(sql, args, opts), do: Dawarich.ScratchRepo.query!(sql, args, opts)
  end

  setup do
    start_oban(@oban)

    for name <- ~w(ARCHIVE_RAW_DATA SELF_HOSTED) do
      previous = System.get_env(name)

      on_exit(fn ->
        if previous, do: System.put_env(name, previous), else: System.delete_env(name)
      end)
    end

    System.put_env("ARCHIVE_RAW_DATA", "true")
    System.put_env("SELF_HOSTED", "false")
    :ok
  end

  @tag a12f3b_case: "G04a"
  test "archive and digest schedules preserve no catch-up and joint mail ownership" do
    for name <-
          ~w(raw_data_archive_job raw_data_clear_job raw_data_verify_job lite_archival_warning_job monthly_digest_scheduling_job yearly_digest_scheduling_job) do
      assert %{kind: :cron, catch_up: false} =
               Enum.find(Registry.entries(), &(&1.key == "cron:" <> name))
    end

    assert Scheduling.period(ScratchRepo, :monthly, ~U[2026-03-31 23:30:00Z], "Berlin") == %{
             year: 2026,
             month: 3
           }

    assert Scheduling.period(ScratchRepo, :yearly, ~U[2025-12-31 23:30:00Z], "Berlin") == %{
             year: 2025,
             month: nil
           }

    [[user]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES ('cron-archive@example.test',now(),now()) RETURNING id"
      )

    for worker <- [ArchiveWorker, ClearWorker] do
      Ownership.put!(ScratchRepo, worker.key(), :oban)
      assert worker.perform(%Oban.Job{args: %{}, conf: %Oban.Config{name: @oban}}) == :ok
      assert [[args]] = rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [inspect(worker)])
      assert args["user_id"] == user
    end

    Ownership.put!(ScratchRepo, ArchivalWarningWorker.key(), :sidekiq, pinned: true)

    assert rows("SELECT owner,pinned FROM phoenix.job_owners WHERE key=ANY($1) ORDER BY key", [
             Ownership.joint_keys(ArchivalWarningWorker.key())
           ]) == [["sidekiq", true], ["sidekiq", true]]

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  @tag a12f3b_case: "G04b"
  test "digest and warning scheduling failure leaves no half-owned mail" do
    [[user]] =
      rows(
        "INSERT INTO users(email,plan,settings,created_at,updated_at) VALUES ('cron-warning@example.test',0,'{}',now(),now()) RETURNING id"
      )

    rows(
      "INSERT INTO points(user_id,timestamp,created_at,updated_at) VALUES ($1,1744594100,now(),now())",
      [user]
    )

    Ownership.put!(ScratchRepo, ArchivalWarningWorker.key(), :oban)

    assert ArchivalWarningWorker.run(RollbackRepo, @oban, @now, "Berlin") ==
             {:error, :mail_insert_failed}

    assert rows("SELECT settings->'archival_warnings' FROM users WHERE id=$1", [user]) == [[nil]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert ArchivalWarningWorker.run(ScratchRepo, @oban, @now, "Berlin") == :ok

    assert [[%{"11_5mo" => mark}]] =
             rows("SELECT settings->'archival_warnings' FROM users WHERE id=$1", [user])

    assert [[%{"epoch" => ^mark, "user_id" => ^user}]] =
             rows(
               "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Mail.ArchivalApproachingWorker'"
             )

    assert ArchivalWarningWorker.run(ScratchRepo, @oban, @now, "Berlin") == :ok
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
  end
end
