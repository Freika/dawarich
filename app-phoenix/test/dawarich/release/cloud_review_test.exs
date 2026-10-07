defmodule Dawarich.Release.CloudReviewTest do
  use Dawarich.JobsCase, async: false
  import Dawarich.AnomalyCase
  alias Dawarich.Release.{Cloud, CloudJobs}
  alias Dawarich.ReleaseMigrator.{Jobs, Lease}
  alias Dawarich.Jobs.Ownership

  setup do
    rows("DELETE FROM phoenix.release_migration_jobs")
    rows("DELETE FROM phoenix.release_migrator_leases")
    rows("DELETE FROM public.data_migrations")

    rows("INSERT INTO public.data_migrations(version) SELECT unnest($1::text[])", [
      Dawarich.RailsTree.versions("data")
    ])

    rows("DELETE FROM public.ar_internal_metadata WHERE key='phoenix_native_baseline'")
    :ok
  end

  test "reconciliation adopts the real enqueued anomalies job" do
    for class <- [
          "DataMigrations::RecalculateAnomaliesJob",
          "DataMigrations::RecalculatePerTrackerTracksJob"
        ] do
      rows("DELETE FROM phoenix.release_migration_jobs")
      rows("DELETE FROM oban.oban_jobs")

      assert {:ok, :ok} =
               ScratchRepo.transaction(fn ->
                 Jobs.insert!(
                   ScratchRepo,
                   "20260823190000",
                   {class, [], 0},
                   :enqueue
                 )
               end)

      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
      original = rows("SELECT args FROM oban.oban_jobs")

      assert :ok =
               Lease.with_lease(ScratchRepo, [], fn lease ->
                 CloudJobs.reconcile(ScratchRepo, lease)
               end)

      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
      assert rows("SELECT args FROM oban.oban_jobs") == original

      assert :ok =
               Lease.with_lease(ScratchRepo, [], fn lease ->
                 CloudJobs.reconcile(ScratchRepo, lease)
               end)

      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
    end
  end

  test "achievement publication is not completed data work" do
    opts = [
      env: %{
        "SELF_HOSTED" => "false",
        "MANAGER_URL" => "https://manager.example.invalid",
        "JWT_SECRET_KEY" => "synthetic-l1-config"
      },
      command: fn _ -> {:ok, nil} end
    ]

    assert :ok = Cloud.migrate(ScratchRepo, opts)
    oban = Dawarich.Release.CloudReviewTest.Oban
    start_oban(oban)
    Ownership.put!(ScratchRepo, "command:achievements.bulk_check", :oban)
    Ownership.put!(ScratchRepo, "command:achievements.check", :oban)
    user = user!()
    rows("UPDATE users SET status=1 WHERE id=$1", [user])
    point!(user, 1_700_000_000, {13.4, 52.5})

    rows(
      "INSERT INTO countries(iso_a2,iso_a3,name,created_at,updated_at) VALUES('ZZ','ZZZ','Synthetic',now(),now())"
    )

    codes = Dawarich.Achievements.Registry.subdivision_codes() |> MapSet.to_list()

    rows(
      "INSERT INTO regions(code,geom,created_at,updated_at) SELECT unnest($1::text[]),ST_GeomFromText('MULTIPOLYGON EMPTY',4326),now(),now() ON CONFLICT(code) DO NOTHING",
      [codes]
    )

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               Jobs.insert!(
                 ScratchRepo,
                 "20260804070000",
                 {"DataMigrations::BackfillAchievementsJob", [], 0},
                 :record
               )
             end)

    assert :ok =
             Lease.with_lease(ScratchRepo, [], fn lease ->
               CloudJobs.reconcile(ScratchRepo, lease)
             end)

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(oban, queue: :maintenance, with_scheduled: true)

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Achievements.BulkCheckWorker' AND state<>'completed'"
           ) == [[1]]

    assert {CloudJobs.ready?(ScratchRepo), Cloud.ready?(ScratchRepo, opts)} == {false, false}

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(oban, queue: :projections, with_scheduled: true, with_limit: 1)

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Achievements.CheckWorker' AND state<>'completed'"
           ) == [[1]]

    before = rows("SELECT row_to_json(t) FROM phoenix.processed_commands t ORDER BY event_id")
    assert {CloudJobs.ready?(ScratchRepo), Cloud.ready?(ScratchRepo, opts)} == {false, false}

    assert rows("SELECT row_to_json(t) FROM phoenix.processed_commands t ORDER BY event_id") ==
             before

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(oban, queue: :projections, with_scheduled: true)

    assert CloudJobs.ready?(ScratchRepo)
    assert Cloud.ready?(ScratchRepo, opts)

    assert :ok =
             Lease.with_lease(ScratchRepo, [], fn lease ->
               CloudJobs.reconcile(ScratchRepo, lease)
             end)

    rows("DELETE FROM oban.oban_jobs")
    assert CloudJobs.ready?(ScratchRepo)
    assert Cloud.ready?(ScratchRepo, opts)
  end

  test "default readiness refuses a missing actual source data version" do
    opts = [
      env: %{
        "SELF_HOSTED" => "false",
        "MANAGER_URL" => "https://manager.example.invalid",
        "JWT_SECRET_KEY" => "synthetic-l1-config"
      },
      command: fn _ -> {:ok, nil} end
    ]

    assert :ok = Cloud.migrate(ScratchRepo, opts)
    versions = Dawarich.RailsTree.versions("data")
    rows("DELETE FROM public.data_migrations")
    rows("INSERT INTO public.data_migrations(version) SELECT unnest($1::text[])", [versions])
    assert Cloud.ready?(ScratchRepo, opts)
    rows("DELETE FROM public.data_migrations WHERE version='20250518174305'")
    refute Cloud.ready?(ScratchRepo, opts)
    rows("INSERT INTO public.data_migrations(version) VALUES('20250518174305')")
    assert Cloud.ready?(ScratchRepo, opts)
    rows("INSERT INTO public.data_migrations(version) VALUES('20999999999999')")
    refute Cloud.ready?(ScratchRepo, opts)
  end

  test "publication and an account update use a consistent lock order" do
    user = user!()
    event = Ecto.UUID.generate()
    Ownership.put!(ScratchRepo, "command:mail.user.welcome", :oban)
    parent = self()

    intent = fn ->
      Dawarich.AfterCommit.intent(
        ScratchRepo,
        "mail.user.welcome",
        %{"user_id" => user, "locale" => "en"},
        event_id: event
      )
    end

    a =
      Task.async(fn ->
        try do
          ScratchRepo.transaction(fn ->
            rows("SELECT id FROM users WHERE id=$1 FOR UPDATE", [user])
            [[backend]] = rows("SELECT pg_backend_pid()")
            send(parent, {:user_locked, self(), backend})

            receive do
              :publish -> intent.()
            end
          end)
        rescue
          e in Postgrex.Error -> {:error, e.postgres.code}
        end
      end)

    assert_receive {:user_locked, pid, first_backend}

    b =
      Task.async(fn ->
        try do
          ScratchRepo.transaction(fn ->
            [[backend]] = rows("SELECT pg_backend_pid()")
            send(parent, {:publishing, backend})
            intent.()
          end)
        rescue
          e in Postgrex.Error -> {:error, e.postgres.code}
        end
      end)

    assert_receive {:publishing, second_backend}
    wait_for_block(second_backend, first_backend, System.monotonic_time(:millisecond) + 2000)
    send(pid, :publish)
    results = [Task.await(a, 5000), Task.await(b, 5000)]
    assert results == [{:ok, :ok}, {:ok, :ok}]
  end

  defp wait_for_block(second, first, deadline) do
    if rows("SELECT $2=ANY(pg_blocking_pids($1))", [second, first]) != [[true]] do
      assert System.monotonic_time(:millisecond) < deadline
      :erlang.yield()
      wait_for_block(second, first, deadline)
    end
  end

  @tag timeout: 20000
  test "Cloud transport has a ten second total cap despite photo config" do
    previous = Application.get_env(:dawarich, :photo_source_timeout)
    Application.put_env(:dawarich, :photo_source_timeout, 20000)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :photo_source_timeout, previous),
        else: Application.delete_env(:dawarich, :photo_source_timeout)
    end)

    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    on_exit(fn -> :gen_tcp.close(listen) end)
    {:ok, {_, port}} = :inet.sockname(listen)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listen)
        :gen_tcp.recv(socket, 0, 1000)
        Process.sleep(10500)
        :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
        :gen_tcp.close(socket)
      end)

    started = System.monotonic_time(:millisecond)

    result =
      Dawarich.Cloud.ProviderHTTP.post(:manager, "/api/v1/users", [], "{}",
        test_loopback: true,
        env: %{"MANAGER_URL" => "http://127.0.0.1:#{port}"}
      )

    elapsed = System.monotonic_time(:millisecond) - started
    Task.await(server, 15000)
    assert {result, elapsed <= 10100} == {{:error, :timeout}, true}
  end
end
