defmodule Dawarich.Metrics.Poller do
  @moduledoc false
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    sample()
    schedule()
    {:ok, opts}
  end

  @impl true
  def handle_info(:sample, state) do
    sample()
    schedule()
    {:noreply, state}
  end

  def sample do
    :telemetry.execute(
      [:dawarich, :runtime],
      %{memory: :erlang.memory(:total), processes: :erlang.system_info(:process_count)},
      %{}
    )
  end

  defp schedule, do: Process.send_after(self(), :sample, 15_000)
end
