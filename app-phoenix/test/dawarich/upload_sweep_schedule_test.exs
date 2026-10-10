defmodule Dawarich.UploadSweepScheduleTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.{Uploads, Storage}
  alias Dawarich.Accounts.Scope

  setup do
    user = Dawarich.Test.RailsUser.insert!(%{id: 13231, email: "sweep-owner@example.invalid"})
    root = Path.join(System.tmp_dir!(), "sweep-schedule-" <> Ecto.UUID.generate())
    on_exit(fn -> File.rm_rf!(root) end)
    %{scope: Scope.for_user(user, "en"), local: %{service: "local", root: root}}
  end

  test "repeated reservations retain one sweep at the earliest required deadline", c do
    for ttl <- [86400, 7200, 3600, 18000, 600, 800] do
      reserve(c, ttl)
      assert [[1]] == outstanding_count()

      assert [[scheduled]] =
               rows(
                 "SELECT scheduled_at FROM oban.oban_jobs WHERE worker='Dawarich.Uploads.SweepWorker' AND state IN ('available','scheduled','retryable')"
               )

      [[earliest]] =
        rows("SELECT min(expires_at) FROM phoenix.native_uploads WHERE state='pending'")

      assert abs(NaiveDateTime.diff(scheduled, earliest, :microsecond)) < 10000
    end
  end

  test "repeated remote cleanup cycles keep one successor and advance a far-future sweep", c do
    ref = reserve(c, 86400)
    assert {:ok, :cancelled} = Uploads.cancel(c.scope, ref)

    remote =
      Storage.S3.config!(%{
        "AWS_ACCESS_KEY_ID" => "synthetic",
        "AWS_SECRET_ACCESS_KEY" => "synthetic",
        "AWS_REGION" => "eu-central-1",
        "AWS_BUCKET" => "synthetic"
      })
      |> Map.merge(%{service: "s3", stored_service: "local", root: c.local.root})
      |> Map.update!(
        :ex_aws,
        &Keyword.merge(&1,
          http_client: Dawarich.Test.UploadCleanupHttp,
          http_opts: [
            respond: fn :delete, _, _ -> {:ok, %{status_code: 204, headers: [], body: ""}} end
          ]
        )
      )

    for _ <- 1..8 do
      assert :ok =
               Dawarich.Uploads.CleanupWorker.run(%{"reference" => ref},
                 repo: Repo,
                 services: %{"local" => remote}
               )

      assert [[1]] == outstanding_count()

      [[scheduled]] =
        rows(
          "SELECT scheduled_at FROM oban.oban_jobs WHERE worker='Dawarich.Uploads.SweepWorker' AND state IN ('available','scheduled','retryable')"
        )

      [[deadline]] =
        rows("SELECT cleanup_at FROM phoenix.native_uploads WHERE reference=$1", [ref])

      assert NaiveDateTime.compare(scheduled, deadline) != :gt
      assert NaiveDateTime.diff(scheduled, NaiveDateTime.utc_now()) <= 300

      rows(
        "UPDATE oban.oban_jobs SET state='completed' WHERE worker='Dawarich.Uploads.CleanupWorker'"
      )

      rows(
        "UPDATE phoenix.native_uploads SET cleanup_at=timezone('UTC',now())-interval '1 second' WHERE reference=$1",
        [ref]
      )

      [[id]] =
        rows(
          "SELECT id FROM oban.oban_jobs WHERE worker='Dawarich.Uploads.SweepWorker' AND state IN ('available','scheduled','retryable')"
        )

      rows("UPDATE oban.oban_jobs SET state='executing' WHERE id=$1", [id])
      assert {:ok, 0} = Uploads.sweep(repo: Repo)
      rows("UPDATE oban.oban_jobs SET state='completed' WHERE id=$1", [id])
      assert [[1]] == outstanding_count()
      assert {:ok, 0} = Uploads.sweep(repo: Repo)
      assert [[1]] == outstanding_count()
    end
  end

  defp outstanding_count,
    do:
      rows(
        "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Uploads.SweepWorker' AND state IN ('available','scheduled','retryable')"
      )

  defp reserve(c, ttl) do
    attrs = %{
      filename: "schedule.gpx",
      byte_size: 6,
      checksum: Base.encode64(:crypto.hash(:md5, "<gpx/>")),
      content_type: "application/gpx+xml"
    }

    assert {:ok, ref} =
             Uploads.reserve(c.scope, attrs, %{
               repo: Repo,
               storage: c.local,
               kind: :imports,
               ttl: ttl
             })

    ref
  end
end
