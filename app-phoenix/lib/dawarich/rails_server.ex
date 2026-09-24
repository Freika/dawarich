defmodule Dawarich.RailsServer do
  @moduledoc false
  use GenServer

  @grace_ms 8_000

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: @grace_ms + 2_000
    }
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    [command | args] = Keyword.fetch!(opts, :argv)

    executable =
      System.find_executable(command) || raise(ArgumentError, "#{command} is not on PATH")

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args,
        env: [{~c"RELEASE_COOKIE", false}]
      ])

    {:ok,
     %{
       port: port,
       sink: Keyword.get_lazy(opts, :sink, &stdout_sink/0),
       on_exit: Keyword.get(opts, :on_exit, &System.stop/1),
       signal: Keyword.get(opts, :signal, &default_signal/2)
     }}
  end

  defp stdout_sink do
    out = Port.open({:fd, 0, 1}, [:binary, :out])
    &Port.command(out, &1)
  end

  defp default_signal(os_pid, sig), do: System.cmd("kill", [sig, os_pid], stderr_to_stdout: true)

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    state.sink.(data)
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    drain_data(port, state.sink)
    state.on_exit.(status)
    {:stop, :normal, %{state | port: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{port: nil}), do: :ok

  def terminate(_reason, %{port: port, sink: sink, signal: signal}) do
    case drain_pending(port, sink) do
      :exited ->
        :ok

      :running ->
        case Port.info(port, :os_pid) do
          {:os_pid, os_pid} -> stop_command(port, Integer.to_string(os_pid), sink, signal)
          nil -> :ok
        end
    end
  end

  defp stop_command(port, os_pid, sink, signal) do
    signal.(os_pid, "-TERM")
    deadline = System.monotonic_time(:millisecond) + @grace_ms

    if await_exit(port, sink, deadline) == :timeout do
      signal.(os_pid, "-KILL")
    end

    :ok
  end

  defp await_exit(port, sink, deadline) do
    receive do
      {^port, {:data, data}} ->
        sink.(data)
        await_exit(port, sink, deadline)

      {^port, {:exit_status, _}} ->
        :ok
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> :timeout
    end
  end

  defp drain_pending(port, sink) do
    receive do
      {^port, {:data, data}} ->
        sink.(data)
        drain_pending(port, sink)

      {^port, {:exit_status, _}} ->
        :exited
    after
      0 -> :running
    end
  end

  defp drain_data(port, sink) do
    receive do
      {^port, {:data, data}} ->
        sink.(data)
        drain_data(port, sink)
    after
      0 -> :ok
    end
  end
end
