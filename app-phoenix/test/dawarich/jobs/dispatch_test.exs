defmodule Dawarich.Jobs.DispatchTest do
  use Dawarich.JobsCase

  import ExUnit.CaptureLog

  alias Dawarich.Jobs.{Dispatch, Outbox, TestEchoWorker}

  defmodule PoisonWorker do
    @moduledoc false
    use Oban.Worker, queue: :default

    def args_from_command(_version, _payload), do: {:ok, %{"at" => {:not, :json}}}

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  @oban Dawarich.DispatchTestOban
  @live Dawarich.DispatchTestLiveOban

  setup do
    start_oban(@oban)
    :ok
  end

  defp commands("test.echo"), do: {:ok, TestEchoWorker}
  defp commands("test.poison"), do: {:ok, PoisonWorker}
  defp commands(_type), do: :error

  defp dispatch(extra \\ []),
    do:
      Dispatch.run(Keyword.merge([repo: ScratchRepo, oban: @oban, commands: &commands/1], extra))

  defp with_lock_timeout(fun) do
    ScratchRepo.transaction(fn ->
      ScratchRepo.query!("SET LOCAL lock_timeout = '50ms'", [], log: false)
      fun.()
    end)
  end

  defp jobs, do: rows("SELECT id, args, meta FROM oban.oban_jobs ORDER BY id")

  defp outbox_state(id),
    do:
      rows("SELECT state, oban_job_id, error_code FROM public.job_outbox WHERE event_id = $1", [
        Ecto.UUID.dump!(id)
      ])

  test "dispatches a due row as one Oban job carrying the event id, in one transaction" do
    id = outbox!(payload: %{"n" => 1})

    assert dispatch() == %{dispatched: 1}
    assert [[job_id, %{"n" => 1, "event_id" => ^id}, %{"command_version" => 1}]] = jobs()
    assert [["dispatched", ^job_id, nil]] = outbox_state(id)
  end

  test "a row scheduled in the future waits in the outbox until the relay's clock reaches it" do
    id = outbox!(payload: %{"n" => 2}, scheduled_at: DateTime.add(DateTime.utc_now(), 3600))

    assert dispatch() == %{}
    assert jobs() == []
    assert [["pending", nil, nil]] = outbox_state(id)

    later = DateTime.add(DateTime.utc_now(), 7200)

    assert dispatch(now: later) == %{dispatched: 1}

    assert [[dispatched_at]] =
             rows("SELECT dispatched_at FROM public.job_outbox WHERE event_id = $1", [
               Ecto.UUID.dump!(id)
             ])

    assert DateTime.compare(dispatched_at, later) == :eq
  end

  test "running again after a commit delivers nothing twice" do
    outbox!(payload: %{"n" => 3})

    assert dispatch() == %{dispatched: 1}
    assert dispatch() == %{}
    assert length(jobs()) == 1
  end

  for stage <- [:claimed, :inserted, :acknowledged] do
    test "a crash at #{stage} leaves the row pending and no job" do
      id = outbox!(payload: %{"n" => 4})
      stage = unquote(stage)

      assert_raise RuntimeError, "crash at #{stage}", fn ->
        dispatch(
          hook: fn
            ^stage, _row -> raise "crash at #{stage}"
            _other, _row -> :ok
          end
        )
      end

      assert jobs() == []
      assert [["pending", nil, nil]] = outbox_state(id)
      assert dispatch() == %{dispatched: 1}
    end
  end

  test "unknown types, unsupported versions and invalid payloads are quarantined once, with a safe code" do
    unknown = outbox!(command_type: "nope.nope")
    version = outbox!(command_version: 9)
    payload = outbox!(payload: %{"n" => "one"})

    assert dispatch() == %{quarantined: 3}
    assert [["quarantined", nil, "unknown_command"]] = outbox_state(unknown)
    assert [["quarantined", nil, "unsupported_version"]] = outbox_state(version)
    assert [["quarantined", nil, "invalid_payload"]] = outbox_state(payload)
    assert dispatch() == %{}
    assert jobs() == []
  end

  test "a decoder that raises quarantines only its own row; the rest of the batch is delivered" do
    bad =
      outbox!(command_type: "test.raises", scheduled_at: DateTime.add(DateTime.utc_now(), -60))

    good = outbox!(payload: %{"n" => 12})

    raising = fn
      "test.raises" -> raise ArgumentError, "decoder bug"
      type -> commands(type)
    end

    log =
      capture_log(fn ->
        assert Dispatch.run(repo: ScratchRepo, oban: @oban, commands: raising) == %{
                 dispatched: 1,
                 quarantined: 1
               }
      end)

    assert [["quarantined", nil, "decoder_error"]] = outbox_state(bad)
    assert [["dispatched", _, nil]] = outbox_state(good)
    assert log =~ bad
    assert log =~ "ArgumentError"
    refute log =~ "decoder bug"
  end

  @tag :capture_log
  test "a row whose decoded args cannot be encoded is quarantined alone; the rest of the batch is delivered" do
    poison =
      outbox!(command_type: "test.poison", scheduled_at: DateTime.add(DateTime.utc_now(), -60))

    good = outbox!(payload: %{"n" => 16})

    assert dispatch() == %{dispatched: 1, quarantined: 1}
    assert [["quarantined", nil, "decoder_error"]] = outbox_state(poison)
    assert [["dispatched", _, nil]] = outbox_state(good)
  end

  test "a second relay skips the row the first one holds" do
    id = outbox!(payload: %{"n" => 5})
    parent = self()

    first =
      Task.async(fn ->
        dispatch(
          hook: fn
            :claimed, _row ->
              send(parent, :holding)

              receive do
                :go -> :ok
              end

            _stage, _row ->
              :ok
          end
        )
      end)

    assert_receive :holding, 5_000
    assert with_lock_timeout(fn -> dispatch() end) == {:ok, %{}}
    send(first.pid, :go)
    assert Task.await(first) == %{dispatched: 1}
    assert [["dispatched", _, nil]] = outbox_state(id)
    assert length(jobs()) == 1
  end

  @tag :capture_log
  test "a connection dropped between insert and acknowledgement rolls both back" do
    id = outbox!(payload: %{"n" => 6})

    error =
      catch_error(
        dispatch(
          hook: fn
            :inserted, _row ->
              [[pid]] = rows("SELECT pg_backend_pid()")
              Task.await(Task.async(fn -> rows("SELECT pg_terminate_backend($1)", [pid]) end))

            _stage, _row ->
              :ok
          end
        )
      )

    assert match?(%DBConnection.ConnectionError{}, error) or
             match?(%Postgrex.Error{postgres: %{code: :admin_shutdown}}, error)

    assert jobs() == []
    assert [["pending", nil, nil]] = outbox_state(id)
    assert dispatch() == %{dispatched: 1}
  end

  test "a database error inside the Oban insert surfaces as itself, without Oban's retries" do
    id = outbox!(payload: %{"n" => 15})
    parent = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!("LOCK TABLE oban.oban_jobs IN SHARE MODE", [], log: false)
          send(parent, :holding)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :holding, 5_000
    error = assert_raise Postgrex.Error, fn -> with_lock_timeout(fn -> dispatch() end) end
    send(holder.pid, :release)
    assert Task.await(holder) == {:ok, :ok}

    assert error.postgres.code == :lock_not_available
    assert jobs() == []
    assert [["pending", nil, nil]] = outbox_state(id)
  end

  test "an Oban unique conflict still acknowledges, pointing at the existing job" do
    first = outbox!(payload: %{"n" => 7})
    second = outbox!(payload: %{"n" => 7})

    assert dispatch() == %{dispatched: 2}
    assert [[job_id, _, _]] = jobs()
    assert [["dispatched", ^job_id, nil]] = outbox_state(first)
    assert [["dispatched", ^job_id, nil]] = outbox_state(second)
  end

  test "a unique job another relay's open transaction holds is acknowledged as deduped_locked" do
    start_oban(@live, testing: :disabled, stager: false, peer: false)
    held = outbox!(payload: %{"n" => 14}, scheduled_at: DateTime.add(DateTime.utc_now(), -60))
    other = outbox!(payload: %{"n" => 14})
    parent = self()

    first =
      Task.async(fn ->
        dispatch(
          oban: @live,
          limit: 1,
          hook: fn
            :inserted, _row ->
              send(parent, :holding)

              receive do
                :go -> :ok
              end

            _stage, _row ->
              :ok
          end
        )
      end)

    assert_receive :holding, 5_000
    assert with_lock_timeout(fn -> dispatch(oban: @live) end) == {:ok, %{dispatched: 1}}
    send(first.pid, :go)
    assert Task.await(first) == %{dispatched: 1}

    assert [[job_id, %{"n" => 14}, _meta]] = jobs()
    assert [["dispatched", ^job_id, nil]] = outbox_state(held)
    assert [["dispatched", nil, "deduped_locked"]] = outbox_state(other)
  end

  test "the relay writes delivery columns only" do
    id = outbox!(payload: %{"n" => 8})

    assert Outbox.writable_columns() == [:state, :oban_job_id, :dispatched_at, :error_code]

    assert_raise ArgumentError, ~r/payload/, fn ->
      Outbox.update_delivery!(ScratchRepo, id, payload: %{})
    end
  end

  test "pruning removes only dispatched rows older than the cutoff" do
    old = DateTime.add(DateTime.utc_now(), -8 * 86_400)
    kept = outbox!(payload: %{"n" => 9})
    gone = outbox!(payload: %{"n" => 10})
    pending = outbox!(payload: %{"n" => 11}, scheduled_at: DateTime.add(DateTime.utc_now(), 3600))
    quarantined = outbox!(payload: %{"n" => 13})

    Outbox.update_delivery!(ScratchRepo, kept,
      state: "dispatched",
      dispatched_at: DateTime.utc_now()
    )

    Outbox.update_delivery!(ScratchRepo, gone, state: "dispatched", dispatched_at: old)

    Outbox.update_delivery!(ScratchRepo, quarantined,
      state: "quarantined",
      dispatched_at: old,
      error_code: "invalid_payload"
    )

    assert Outbox.prune!(ScratchRepo, DateTime.add(DateTime.utc_now(), -7 * 86_400)) == 1
    assert [_] = outbox_state(kept)
    assert [] = outbox_state(gone)
    assert [_] = outbox_state(pending)
    assert [_] = outbox_state(quarantined)
  end
end
