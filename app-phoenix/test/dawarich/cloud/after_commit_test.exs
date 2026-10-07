defmodule Dawarich.Cloud.AfterCommitTest do
  use Dawarich.JobsCase, async: false
  import Dawarich.AnomalyCase
  alias Dawarich.AfterCommit
  alias Dawarich.AfterCommit.Callback
  alias Dawarich.Jobs.{Ownership, Processed}

  setup do
    user = user!()
    Ownership.put!(ScratchRepo, "command:mail.user.welcome", :oban)
    %{user: user, event: Ecto.UUID.generate()}
  end

  test "L1 callback intent rolls back with its account and never calls HTTP before commit", ctx do
    parent = self()
    assert {:error, :transaction_required} = intent(ctx)

    assert {:error, :cancel} =
             ScratchRepo.transaction(fn ->
               assert :ok = intent(ctx)

               assert {:error, :transaction_required} =
                        Callback.run(ScratchRepo, ctx.event, "welcome", fn ->
                          send(parent, :http)
                          :ok
                        end)

               task = Task.async(fn -> rows("SELECT count(*) FROM public.job_outbox") end)
               assert Task.await(task) == [[0]]
               ScratchRepo.rollback(:cancel)
             end)

    assert rows("SELECT count(*) FROM public.job_outbox") == [[0]]
    refute Processed.done?(ScratchRepo, ctx.event)
    refute_received :http
  end

  test "L1 callback intent preserves identity due time and native ownership across replay", ctx do
    at = ~U[2030-01-01 00:00:00.000000Z]
    parent = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> :ok
          end

          ScratchRepo.transaction(fn -> intent(ctx, scheduled_at: at) end)
        end)
      end

    for _ <- tasks do
      assert_receive {:ready, pid}
      send(pid, :go)
    end

    for task <- tasks, do: assert(Task.await(task) == {:ok, :ok})

    assert rows("SELECT event_id,dedupe_key,aggregate_id,scheduled_at FROM public.job_outbox") ==
             [[Ecto.UUID.dump!(ctx.event), ctx.event, ctx.user, at]]

    assert :ok = Callback.run(ScratchRepo, ctx.event, "welcome", fn -> :ok end)
    rows("DELETE FROM public.job_outbox")
    assert {:ok, :ok} = ScratchRepo.transaction(fn -> intent(ctx) end)
    assert rows("SELECT count(*) FROM public.job_outbox") == [[0]]
    Ownership.put!(ScratchRepo, "command:mail.user.welcome", :sidekiq)

    assert {:ok, {:error, :callback_owner}} =
             ScratchRepo.transaction(fn -> intent(%{ctx | event: Ecto.UUID.generate()}) end)

    assert {:ok, {:error, "invalid_payload"}} =
             ScratchRepo.transaction(fn ->
               AfterCommit.intent(
                 ScratchRepo,
                 "mail.user.welcome",
                 %{"user_id" => ctx.user, "locale" => "en", "url" => "https://untrusted.test"},
                 event_id: Ecto.UUID.generate()
               )
             end)

    assert {:ok, {:error, "unknown_command"}} =
             ScratchRepo.transaction(fn ->
               AfterCommit.intent(ScratchRepo, "unknown", %{}, event_id: Ecto.UUID.generate())
             end)

    Ownership.put!(ScratchRepo, "command:mail.user.archival_approaching", :oban)

    rows(
      "UPDATE phoenix.job_owners SET owner='sidekiq' WHERE key='cron:lite_archival_warning_job'"
    )

    assert {:ok, {:error, :callback_owner}} =
             ScratchRepo.transaction(fn ->
               AfterCommit.intent(
                 ScratchRepo,
                 "mail.user.archival_approaching",
                 %{"user_id" => ctx.user, "locale" => "en", "epoch" => "synthetic"},
                 event_id: Ecto.UUID.generate()
               )
             end)
  end

  test "L1 committed callback serializes replay and retains retry after transport failure", ctx do
    assert {:error, :timeout} =
             Callback.run(ScratchRepo, ctx.event, "welcome", fn -> {:error, :timeout} end)

    refute Processed.done?(ScratchRepo, ctx.event)
    parent = self()

    first =
      Task.async(fn ->
        Callback.run(ScratchRepo, ctx.event, "welcome", fn ->
          refute ScratchRepo.in_transaction?()
          send(parent, {:sending, self()})

          receive do
            :accepted -> :ok
          end
        end)
      end)

    assert_receive {:sending, pid}

    second =
      Task.async(fn ->
        Callback.run(ScratchRepo, ctx.event, "welcome", fn ->
          send(parent, :duplicate)
          :ok
        end)
      end)

    send(pid, :accepted)
    assert Task.await(first) == :ok
    assert Task.await(second) == :ok
    refute_received :duplicate
    assert Processed.done?(ScratchRepo, ctx.event)
  end

  test "L1 callback reuses provider idempotency after accepted send loses local receipt", ctx do
    provider = start_supervised!({Agent, fn -> MapSet.new() end})
    parent = self()

    effect = fn ->
      identity = AfterCommit.identity(ctx.event, "provider")
      Agent.update(provider, &MapSet.put(&1, identity))
      send(parent, {:accepted, self()})

      receive do
        :receipt -> :ok
      end
    end

    {pid, monitor} =
      spawn_monitor(fn -> Callback.run(ScratchRepo, ctx.event, "welcome", effect) end)

    assert_receive {:accepted, ^pid}
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    refute Processed.done?(ScratchRepo, ctx.event)
    retry = Task.async(fn -> Callback.run(ScratchRepo, ctx.event, "welcome", effect) end)
    assert_receive {:accepted, retry_pid}
    send(retry_pid, :receipt)
    assert Task.await(retry) == :ok
    assert Agent.get(provider, &MapSet.size/1) == 1
    assert Processed.done?(ScratchRepo, ctx.event)
  end

  defp intent(ctx, opts \\ []) do
    AfterCommit.intent(
      ScratchRepo,
      "mail.user.welcome",
      %{"user_id" => ctx.user, "locale" => "en"},
      Keyword.merge([event_id: ctx.event, dedupe_key: ctx.event, aggregate_id: ctx.user], opts)
    )
  end
end
