defmodule Dawarich.Jobs.DispatchTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Dispatch, Outbox, TestEchoWorker}

  @oban Dawarich.DispatchTestOban

  setup do
    start_oban(@oban)
    :ok
  end

  defp commands("test.echo"), do: {:ok, TestEchoWorker}
  defp commands(_type), do: :error

  defp dispatch(extra \\ []),
    do: Dispatch.run([repo: ScratchRepo, oban: @oban, commands: &commands/1] ++ extra)

  defp jobs, do: rows("SELECT id, args FROM oban.oban_jobs ORDER BY id")

  defp outbox_state(id),
    do:
      rows("SELECT state, oban_job_id, error_code FROM public.job_outbox WHERE event_id = $1", [
        Ecto.UUID.dump!(id)
      ])

  test "dispatches a due row as one Oban job carrying the event id, in one transaction" do
    id = outbox!(payload: %{"n" => 1})

    assert dispatch() == %{dispatched: 1}
    assert [[job_id, %{"n" => 1, "event_id" => ^id}]] = jobs()
    assert [["dispatched", ^job_id, nil]] = outbox_state(id)
  end

  test "a row scheduled in the future waits in the outbox" do
    id = outbox!(payload: %{"n" => 2}, scheduled_at: DateTime.add(DateTime.utc_now(), 3600))

    assert dispatch() == %{}
    assert jobs() == []
    assert [["pending", nil, nil]] = outbox_state(id)
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

    assert Dispatch.run(repo: ScratchRepo, oban: @oban, commands: raising) == %{
             dispatched: 1,
             quarantined: 1
           }

    assert [["quarantined", nil, "decoder_error"]] = outbox_state(bad)
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

    assert_receive :holding
    assert dispatch() == %{}
    send(first.pid, :go)
    assert Task.await(first) == %{dispatched: 1}
    assert [["dispatched", _, nil]] = outbox_state(id)
    assert length(jobs()) == 1
  end

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

  test "an Oban unique conflict still acknowledges, pointing at the existing job" do
    first = outbox!(payload: %{"n" => 7})
    second = outbox!(payload: %{"n" => 7})

    assert dispatch() == %{dispatched: 2}
    assert [[job_id, _]] = jobs()
    assert [["dispatched", ^job_id, nil]] = outbox_state(first)
    assert [["dispatched", ^job_id, nil]] = outbox_state(second)
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
