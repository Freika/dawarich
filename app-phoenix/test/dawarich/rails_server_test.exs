defmodule Dawarich.RailsServerTest do
  use ExUnit.Case, async: true

  alias Dawarich.RailsServer

  defp start(argv) do
    test = self()

    start_supervised!(
      {RailsServer,
       argv: argv, sink: &send(test, {:out, &1}), on_exit: &send(test, {:exited, &1})}
    )
  end

  test "forwards the command's output" do
    start(["echo", "puma booted"])
    assert_receive {:out, "puma booted\n"}, 2_000
  end

  test "reports the command's exit status and is not restarted" do
    start(["sh", "-c", "exit 3"])
    assert_receive {:exited, 3}, 2_000
    refute_receive {:exited, _}, 500
  end

  @tag :capture_log
  test "is restarted after an abnormal exit" do
    pid = start(["sh", "-c", "echo up; exec sleep 5"])
    assert_receive {:out, "up\n"}, 2_000

    :sys.terminate(pid, :boom)

    assert_receive {:out, "up\n"}, 2_000
  end

  test "sends SIGTERM to the command when stopped" do
    start([
      "sh",
      "-c",
      "trap 'echo got-term; exit 0' TERM; echo ready; while :; do sleep 0.1; done"
    ])

    assert_receive {:out, "ready\n"}, 2_000

    :ok = stop_supervised(RailsServer)

    assert_receive {:out, "got-term\n"}, 2_000
  end

  test "refuses an executable that is not on PATH" do
    assert {:error, _} = start_supervised({RailsServer, argv: ["definitely-not-a-command"]})
  end

  test "does not signal a command whose exit is already queued at shutdown" do
    race_suspend_before_exit_status(20)
  end

  defp race_suspend_before_exit_status(0) do
    flunk("could not reliably suspend before the queued exit_status was processed")
  end

  defp race_suspend_before_exit_status(retries_left) do
    test = self()

    pid =
      start_supervised!(
        {RailsServer,
         argv: ["sh", "-c", "echo bye; exit 0"],
         sink: &send(test, {:out, &1}),
         on_exit: &send(test, {:exited, &1}),
         signal: fn os_pid, sig -> send(test, {:signalled, os_pid, sig}) end}
      )

    try do
      :sys.suspend(pid)
    catch
      :exit, _ -> :ok
    end

    already_handled =
      receive do
        {:exited, _} -> true
      after
        0 -> false
      end

    if already_handled do
      stop_supervised(RailsServer)
      race_suspend_before_exit_status(retries_left - 1)
    else
      assert wait_for_queued_exit_status(pid)
      :ok = stop_supervised(RailsServer)
      assert_received {:out, "bye\n"}
      refute_received {:signalled, _, _}
    end
  end

  defp wait_for_queued_exit_status(pid) do
    wait_for_queued_exit_status(pid, System.monotonic_time(:millisecond) + 2_000)
  end

  defp wait_for_queued_exit_status(pid, deadline) do
    case Process.info(pid, :messages) do
      {:messages, messages} ->
        if Enum.any?(messages, &match?({_port, {:exit_status, _}}, &1)) do
          true
        else
          if System.monotonic_time(:millisecond) >= deadline do
            false
          else
            Process.sleep(10)
            wait_for_queued_exit_status(pid, deadline)
          end
        end

      nil ->
        false
    end
  end
end
