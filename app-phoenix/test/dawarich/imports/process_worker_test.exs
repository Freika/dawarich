defmodule Dawarich.Imports.ProcessWorkerTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.{Lease, ProcessWorker, NormalLifecycle}
  alias Dawarich.Jobs.{Dispatch, Ownership, Processed, Registry}
  alias Dawarich.Test.NormalFormats

  @opts [
    lane: "command:imports.process_normal",
    worker: "Dawarich.Imports.ProcessWorker",
    sources: [nil, 0, 1, 2, 3, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15],
    terminal_statuses: [2, 3]
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "normal-worker-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    old = Application.fetch_env(:dawarich, :jobs_repo)
    old_services = Application.fetch_env(:dawarich, :imports_services)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

    Application.put_env(:dawarich, :imports_services, %{
      "local" => %{service: "local", root: root}
    })

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:dawarich, :jobs_repo, value)
        :error -> Application.delete_env(:dawarich, :jobs_repo)
      end
    end)

    on_exit(fn ->
      case old_services do
        {:ok, value} -> Application.put_env(:dawarich, :imports_services, value)
        :error -> Application.delete_env(:dawarich, :imports_services)
      end
    end)

    %{root: root}
  end

  test "normal command is inert decodes strictly and rehomes through Rails", c do
    c = fixture(c, "csv_known")

    assert %{claimable: false} =
             Enum.find(Registry.entries(), &(&1.key == "command:imports.process_normal"))

    valid = Map.delete(c.job.args, "event_id")
    assert {:ok, ^valid} = ProcessWorker.args_from_command(1, valid)
    assert {:error, "unsupported_version"} = ProcessWorker.args_from_command(2, valid)

    for payload <- [
          %{valid | "import_id" => 0},
          %{valid | "user_id" => "1"},
          %{valid | "time_zone" => "bad/zone"},
          Map.put(valid, "source", 10)
        ] do
      assert {:error, "invalid_payload"} = ProcessWorker.args_from_command(1, payload)
    end

    Ownership.put!(ScratchRepo, "command:imports.process_normal", :sidekiq)

    rows(
      "CREATE FUNCTION public.reject_normal_resume() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.kind='imports.normal_resume' THEN RAISE EXCEPTION 'resume unavailable'; END IF; RETURN NEW; END $$"
    )

    rows(
      "CREATE TRIGGER reject_normal_resume BEFORE INSERT ON phoenix.rails_commands FOR EACH ROW EXECUTE FUNCTION public.reject_normal_resume()"
    )

    try do
      assert_raise Postgrex.Error, ~r/resume unavailable/, fn -> ProcessWorker.perform(c.job) end
      refute Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert [] = rows("SELECT event_id FROM phoenix.import_handoffs")
    after
      rows("DROP TRIGGER reject_normal_resume ON phoenix.rails_commands")
      rows("DROP FUNCTION public.reject_normal_resume()")
    end

    assert :ok = ProcessWorker.perform(c.job)

    assert [["imports.normal_resume", payload]] =
             rows("SELECT kind,payload FROM phoenix.rails_commands")

    assert payload == c.job.args

    reset!(ScratchRepo)
    c = fixture(c, "csv_known")
    rows("UPDATE imports SET source=4,status=3 WHERE id=$1", [c.import.id])
    assert :ok = ProcessWorker.perform(c.job)

    assert [["imports.normal_resume", payload]] =
             rows("SELECT kind,payload FROM phoenix.rails_commands")

    assert payload == c.job.args
    assert [[false]] = rows("SELECT native_fallback FROM phoenix.import_handoffs")
  end

  test "normal and GPX attempts cannot own the same import concurrently", c do
    c = fixture(c, "csv_known")
    parent = self()

    holder =
      Task.async(fn ->
        Lease.with_import(
          ScratchRepo,
          c.job,
          c.import,
          fn _ ->
            send(parent, :holding)

            receive do
              :release -> :ok
            end
          end,
          @opts
        )
      end)

    on_exit(fn -> send(holder.pid, :release) end)
    assert_receive :holding
    rows("UPDATE imports SET source=4 WHERE id=$1", [c.import.id])

    {1, [%{id: gpx}]} =
      ScratchRepo.insert_all(
        "oban_jobs",
        [
          %{
            state: "executing",
            queue: "imports",
            worker: "Dawarich.Imports.ProcessGpxWorker",
            args: c.job.args,
            attempt: 1,
            max_attempts: 3
          }
        ],
        prefix: "oban",
        returning: [:id]
      )

    Ownership.put!(ScratchRepo, "command:imports.process_gpx", :oban)

    assert {:skip, :busy} =
             Lease.with_import(ScratchRepo, %{c.job | id: gpx}, c.import, fn _ -> :ok end)

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)
    rows("UPDATE imports SET source=10 WHERE id=$1", [c.import.id])
    rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])

    assert {:skip, :unavailable} =
             Lease.with_import(ScratchRepo, c.job, c.import, fn _ -> :ok end, @opts)

    assert {:skip, :unavailable} =
             Lease.with_import(
               ScratchRepo,
               %{c.job | attempt: 2, args: Map.put(c.job.args, "event_id", Ecto.UUID.generate())},
               c.import,
               fn _ -> :ok end,
               @opts
             )
  end

  test "captured normal zone reaches the worker unchanged", c do
    c = fixture(c, "csv_known")

    event =
      outbox!(command_type: "imports.process_normal", payload: Map.delete(c.job.args, "event_id"))

    rows(
      "UPDATE users SET settings=jsonb_build_object('timezone','Pacific/Auckland') WHERE id=$1",
      [c.import.user_id]
    )

    start_oban(__MODULE__)
    assert %{dispatched: 1} = Dispatch.run(oban: __MODULE__, repo: ScratchRepo)
    assert [[args]] = rows("SELECT args FROM oban.oban_jobs WHERE args->>'event_id'=$1", [event])
    assert args["time_zone"] == "Europe/Berlin"
    assert ProcessWorker.context(ScratchRepo, %Oban.Job{args: args}).zone == "Europe/Berlin"
  end

  test "normal lease admits real normal sources and preserves GPX defaults", c do
    for source <- [10, 3] do
      reset!(ScratchRepo)
      c = fixture(c, "csv_known")
      rows("UPDATE imports SET source=$2 WHERE id=$1", [c.import.id, source])

      assert {:ok, :admitted} =
               Lease.with_import(
                 ScratchRepo,
                 c.job,
                 c.import,
                 fn lease -> Lease.effect!(lease, fn -> :admitted end) end,
                 @opts
               )

      assert {:skip, :unavailable} =
               Lease.with_import(ScratchRepo, c.job, c.import, fn _ -> :admitted end)

      if source == 3 do
        bytes =
          File.read!(
            Path.expand("../../fixtures/imports/formats/phone_import_signal.input.json", __DIR__)
          )

        [[key]] = rows("SELECT key FROM active_storage_blobs")
        File.write!(Dawarich.Storage.disk_path(c.root, key), bytes)

        rows("UPDATE active_storage_blobs SET filename='phone.json',byte_size=$1,checksum=$2", [
          byte_size(bytes),
          Base.encode64(:crypto.hash(:md5, bytes))
        ])
      end

      assert :ok = ProcessWorker.perform(c.job)

      assert [[2, count]] =
               rows("SELECT status,raw_points FROM imports WHERE id=$1", [c.import.id])

      assert count > 0
    end

    reset!(ScratchRepo)
    c = Dawarich.ImportLeaseFixture.create()
    assert {:ok, :ok} = Lease.with_import(ScratchRepo, c.job, c.import, fn _ -> :ok end)

    assert {:skip, :unavailable} =
             Lease.with_import(ScratchRepo, c.job, c.import, fn _ -> :ok end, @opts)
  end

  test "nil source is detected after unwrap and persisted under fence", c do
    c = fixture(c, "csv_single_zip")
    assert {:ok, :ok} = run(c)

    assert [[10, 2, 2]] =
             rows("SELECT source,status,raw_points FROM imports WHERE id=$1", [c.import.id])

    assert [[2]] = rows("SELECT count(*) FROM points")

    for name <- ~w(v1_profile v2_profile) do
      reset!(ScratchRepo)
      c = fixture(c, name)
      assert :ok = ProcessWorker.perform(c.job)
      assert [[8, 0]] = rows("SELECT source,status FROM imports WHERE id=$1", [c.import.id])

      assert c.expected["jobs"] == [
               %{"type" => "Users::ImportDataJob", "args" => [c.import.id]}
             ]

      assert [["users.import_data", payload]] =
               rows("SELECT kind,payload FROM phoenix.rails_commands")

      assert payload == %{
               "import_id" => c.import.id,
               "user_id" => c.import.user_id,
               "time_zone" => c.expected["zone"],
               "locale" => c.expected["locale"]
             }

      assert [] = rows("SELECT event_id FROM phoenix.import_handoffs")
      assert [] = rows("SELECT import_id FROM phoenix.import_runs")
      assert Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert [] = rows("SELECT id FROM points")
    end
  end

  test "source transition or unknown detection stops stale effects", c do
    for change <- [:source, :blob] do
      reset!(ScratchRepo)
      c = fixture(c, "csv_single_zip")

      assert_raise Dawarich.Imports.LeaseLost, fn ->
        Lease.with_import(
          ScratchRepo,
          c.job,
          c.import,
          fn lease ->
            Dawarich.Imports.ImportState.with_snapshot(lease, fn _ ->
              case change do
                :source -> rows("UPDATE imports SET source=1 WHERE id=$1", [c.import.id])
                :blob -> rows("UPDATE active_storage_blobs SET checksum='changed'")
              end

              Dawarich.Imports.ImportState.source!(lease, 10)
            end)
          end,
          @opts
        )
      end

      source = if change == :source, do: 1, else: nil

      assert [[source, 0, 0]] ==
               rows("SELECT source,status,raw_points FROM imports WHERE id=$1", [c.import.id])

      assert [] = rows("SELECT id FROM points")
    end
  end

  test "unknown normal source preserves localized Rails failure", c do
    for name <- ~w(unknown_en unknown_de) do
      reset!(ScratchRepo)
      c = fixture(c, name)
      assert {:ok, :ok} = run(c)

      assert [[nil, 3, message]] =
               rows("SELECT source,status,error_message FROM imports WHERE id=$1", [c.import.id])

      assert message == c.expected["parent"]["error_message"]
      assert [[title, content]] = rows("SELECT title,content FROM notifications")
      [expected_title, expected_content, "error"] = hd(c.expected["notifications"])
      assert title == expected_title
      [prefix] = Regex.run(~r/^.*?stacktrace: /i, expected_content)
      assert String.starts_with?(content, prefix)
      assert [] = rows("SELECT id FROM points")
    end
  end

  defp fixture(c, name), do: Map.merge(c, NormalFormats.whole!(name, ScratchRepo, c.root))

  defp run(c),
    do:
      Lease.with_import(ScratchRepo, c.job, c.import, &NormalLifecycle.call(&1, c.context), @opts)
end
