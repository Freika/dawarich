defmodule Dawarich.A12f3bE11Test do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Drain, Ownership}
  alias Dawarich.Lite.ArchivalWarningWorker
  alias Dawarich.RawData.{ArchiveFormat, ArchiveWorker, ClearWorker, VerifyWorker}
  alias Dawarich.{I18n, Storage, Wave6Archives, Wave6Fixtures}

  @oban __MODULE__.Oban
  @now ~U[2026-03-29 01:30:00Z]
  @mark "2026-03-29T03:30:00+02:00"

  setup do
    Wave6Fixtures.reset!()
    start_oban(@oban)
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    %{storage: Wave6Fixtures.local_storage!(), key: Wave6Archives.key()}
  end

  @tag a12f3b_case: "E11a"
  test "E11 native owner accepts every retained argument and continuation shape", ctx do
    user = Wave6Fixtures.user!()
    raw = %{"nested" => %{"n" => 1}, "note" => "Straße"}
    point = Wave6Fixtures.point!(user, %{"raw_data" => raw})
    hold_lease!(ScratchRepo, "archive_raw_data:#{user}", "retained-source")

    assert {:snooze, 1} = archive(ctx, %{"user_id" => user, "cursor" => 0})
    assert rows("SELECT raw_data_archived FROM points WHERE id=$1", [point]) == [[false]]
    assert rows("SELECT count(*) FROM points_raw_data_archives") == [[0]]
    assert lease_holders(ScratchRepo, "archive_raw_data:#{user}") == [["retained-source"]]
    assert jobs(ArchiveWorker) == []

    rows("DELETE FROM phoenix.leases WHERE name=$1", ["archive_raw_data:#{user}"])
    assert :ok = archive(ctx, %{"user_id" => user, "cursor" => 0})
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

    assert [[archive_id, true]] =
             rows("SELECT id,verified_at IS NOT NULL FROM points_raw_data_archives")

    assert rows("SELECT raw_data,raw_data_archived,raw_data_archive_id FROM points WHERE id=$1", [
             point
           ]) == [[raw, true, archive_id]]

    assert [[%{"user_id" => ^user, "cursor" => 0}]] = jobs(ArchiveWorker)
    assert lease_holders(ScratchRepo, "archive_raw_data:#{user}") == []
    [path] = Wave6Archives.object_paths(ctx.storage)
    assert {:ok, gzip} = ArchiveFormat.decode(File.read!(path), %{"format_version" => 2}, ctx.key)

    assert Enum.map(ArchiveFormat.lines(gzip), &Jason.decode!/1) == [
             %{"id" => point, "raw_data" => raw}
           ]

    Ownership.put!(ScratchRepo, VerifyWorker.key(), :oban)
    rows("UPDATE points_raw_data_archives SET verified_at=NULL WHERE id=$1", [archive_id])
    assert :ok = VerifyWorker.run(ScratchRepo, storage: ctx.storage, archive_key: ctx.key)

    assert rows("SELECT verified_at IS NOT NULL FROM points_raw_data_archives WHERE id=$1", [
             archive_id
           ]) == [[true]]

    rows("UPDATE points_raw_data_archives SET verified_at=now()-interval '8 days' WHERE id=$1", [
      archive_id
    ])

    hold_lease!(ScratchRepo, "clear_raw_data:#{user}", "retained-source")
    assert :ok = ClearWorker.run(ScratchRepo, @oban, %{"user_id" => user})
    assert rows("SELECT raw_data FROM points WHERE id=$1", [point]) == [[raw]]
    assert lease_holders(ScratchRepo, "clear_raw_data:#{user}") == [["retained-source"]]
    rows("DELETE FROM phoenix.leases WHERE name=$1", ["clear_raw_data:#{user}"])
    assert :ok = ClearWorker.run(ScratchRepo, @oban, %{"user_id" => user}, batch_size: 1)
    assert rows("SELECT raw_data FROM points WHERE id=$1", [point]) == [[%{}]]
    assert lease_holders(ScratchRepo, "clear_raw_data:#{user}") == []

    assert_raise DBConnection.EncodeError, fn ->
      ClearWorker.run(ScratchRepo, @oban, %{"user_id" => user}, batch_size: "invalid")
    end

    assert lease_holders(ScratchRepo, "clear_raw_data:#{user}") == []

    failed = Wave6Fixtures.user!()
    retry_point = Wave6Fixtures.point!(failed, %{"raw_data" => raw})
    corrupt = fn key -> File.write!(Storage.disk_path(ctx.storage.root, key), "garbage") end
    assert :ok = archive(ctx, %{"user_id" => failed, "cursor" => 0}, before_verify: corrupt)

    assert rows("SELECT raw_data,raw_data_archived FROM points WHERE id=$1", [retry_point]) == [
             [raw, false]
           ]

    assert rows("SELECT count(*) FROM points_raw_data_archives WHERE user_id=$1", [failed]) == [
             [0]
           ]

    assert lease_holders(ScratchRepo, "archive_raw_data:#{failed}") == []
    assert :ok = archive(ctx, %{"user_id" => failed, "cursor" => 0})
    assert rows("SELECT raw_data_archived FROM points WHERE id=$1", [retry_point]) == [[true]]

    deleted = Wave6Fixtures.user!(%{"deleted_at" => NaiveDateTime.utc_now()})

    for id <- [-1, deleted] do
      assert :ok = archive(ctx, %{"user_id" => id, "cursor" => 0})
      assert :ok = ClearWorker.run(ScratchRepo, @oban, %{"user_id" => id})
    end

    rows("UPDATE oban.oban_jobs SET state='completed'")

    for worker <- [ArchiveWorker, ClearWorker] do
      assert :ok = worker.run(ScratchRepo, @oban, %{}, enabled: false)
      Ownership.put!(ScratchRepo, worker.key(), :oban)
      assert :ok = worker.run(ScratchRepo, @oban, %{}, enabled: true)
      refute Enum.any?(jobs(worker), fn [args] -> args["user_id"] == deleted end)
      assert Enum.any?(jobs(worker), fn [args] -> args["user_id"] == user end)
    end

    warning = Wave6Fixtures.user!(%{"plan" => 0, "settings" => %{"locale" => "fr"}})
    Wave6Fixtures.point!(warning, %{"timestamp" => 1_745_890_200})
    Ownership.put!(ScratchRepo, ArchivalWarningWorker.key(), :oban)
    Ownership.put!(ScratchRepo, "command:mail.user.archival_approaching", :oban)
    assert :ok = ArchivalWarningWorker.run(ScratchRepo, @oban, @now, "Berlin")

    {:ok, title} =
      I18n.t("fr", "jobs.lite.archival_warning_job.your_oldest_data_will_archive_in_30_days")

    assert rows("SELECT title FROM notifications WHERE user_id=$1", [warning]) == [[title]]

    assert rows("SELECT settings->'archival_warnings' FROM users WHERE id=$1", [warning]) == [
             [%{"11mo" => @mark}]
           ]

    assert :ok = ArchivalWarningWorker.run(ScratchRepo, @oban, @now, "Europe/Berlin")
    assert rows("SELECT count(*) FROM notifications WHERE user_id=$1", [warning]) == [[1]]
    email = Wave6Fixtures.user!(%{"plan" => 0, "settings" => %{"locale" => "es"}})
    Wave6Fixtures.point!(email, %{"timestamp" => 1_744_594_200})
    assert :ok = ArchivalWarningWorker.run(ScratchRepo, @oban, @now, "Berlin")
    assert [[mail_args]] = jobs(Dawarich.Mail.ArchivalApproachingWorker)

    assert %{"user_id" => ^email, "locale" => "es", "epoch" => @mark, "event_id" => event} =
             mail_args

    assert {:ok, _} = Ecto.UUID.cast(event)
    assert :ok = ArchivalWarningWorker.run(ScratchRepo, @oban, @now, "Europe/Berlin")
    assert jobs(Dawarich.Mail.ArchivalApproachingWorker) == [[mail_args]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  @tag a12f3b_case: "E11b"
  test "E11 source accepted chain remains visible until all children settle", ctx do
    user = Wave6Fixtures.user!()
    ids = for n <- 1..3, do: Wave6Fixtures.point!(user, %{"raw_data" => %{"n" => n}})
    args = %{"user_id" => user, "cursor" => 0}
    parent = Oban.insert!(@oban, ArchiveWorker.new(args))
    rows("UPDATE oban.oban_jobs SET state='executing' WHERE id=$1", [parent.id])
    future = DateTime.add(DateTime.utc_now(), 3600)
    stale_args = %{"user_id" => user, "cursor" => List.last(ids) + 1}
    stale = Oban.insert!(@oban, ArchiveWorker.new(stale_args, scheduled_at: future))
    assert stale.state == "scheduled"
    assert stale.scheduled_at == future

    handler = {__MODULE__, make_ref()}
    recipient = self()

    :ok =
      :telemetry.attach(
        handler,
        [:oban, :engine, :insert_job, :stop],
        fn _, _, meta, _ ->
          if meta.conf.name == @oban and meta.job.args == args do
            send(
              recipient,
              {:continuation_lease, lease_holders(ScratchRepo, "archive_raw_data:#{user}")}
            )
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    probe = fn ->
      assert rows("SELECT state FROM oban.oban_jobs WHERE id=$1", [parent.id]) == [["executing"]]
      assert rows("SELECT count(*) FROM oban.oban_jobs WHERE state='executing'") == [[1]]
    end

    assert :ok = archive(ctx, args, chunk_size: 1, before_flag: probe)
    assert_receive {:continuation_lease, []}
    :telemetry.detach(handler)
    rows("UPDATE oban.oban_jobs SET state='completed' WHERE id=$1", [parent.id])
    assert rows("SELECT count(*) FROM points WHERE raw_data_archived=true") == [[1]]
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 2

    assert [[continuation_id, ^args]] =
             rows("SELECT id,args FROM oban.oban_jobs WHERE state='available'")

    assert :ok = archive(ctx, stale_args)
    rows("UPDATE oban.oban_jobs SET state='completed' WHERE id=$1", [stale.id])
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 1
    assert "incomplete_oban" in Drain.status(ScratchRepo).shutdown_reasons
    assert rows("SELECT count(*) FROM points WHERE raw_data_archived=false") == [[2]]

    finish(ctx, continuation_id, args)
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 0
    refute "incomplete_oban" in Drain.status(ScratchRepo).shutdown_reasons
    assert rows("SELECT count(*) FROM points WHERE raw_data_archived=true") == [[3]]
    assert rows("SELECT count(*) FROM phoenix.raw_data_archive_chunks") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  defp archive(ctx, args, opts \\ []),
    do:
      ArchiveWorker.run(
        ScratchRepo,
        @oban,
        args,
        [storage: ctx.storage, archive_key: ctx.key] ++ opts
      )

  defp jobs(worker),
    do:
      rows("SELECT args FROM oban.oban_jobs WHERE worker=$1 AND state<>'completed' ORDER BY id", [
        inspect(worker)
      ])

  defp finish(ctx, id, args) do
    rows("UPDATE oban.oban_jobs SET state='executing' WHERE id=$1", [id])
    assert :ok = archive(ctx, args, chunk_size: 1)
    rows("UPDATE oban.oban_jobs SET state='completed' WHERE id=$1", [id])

    case rows("SELECT id,args FROM oban.oban_jobs WHERE state='available' ORDER BY id") do
      [[next, continuation]] -> finish(ctx, next, continuation)
      [] -> :ok
    end
  end
end
