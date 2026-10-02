defmodule Dawarich.Cable.EventsRelay do
  @moduledoc false
  use GenServer

  require Logger

  alias Dawarich.Cable.TurboEvents

  @poll 1_000
  @backoff 5_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts), do: {:ok, opts, {:continue, :drain}}

  @impl true
  def handle_continue(:drain, state), do: drain(state)

  @impl true
  def handle_info(:drain, state), do: drain(state)

  def next_delay(fun) do
    if fun.() == 0, do: @poll, else: 0
  rescue
    error ->
      Logger.warning("[Cable] events relay: #{inspect(error.__struct__)}")
      @backoff
  end

  defp drain(state) do
    delay = next_delay(fn -> TurboEvents.drain(Dawarich.Jobs.repo(), Dawarich.Repo) end)
    Process.send_after(self(), :drain, delay)
    {:noreply, state}
  end
end
