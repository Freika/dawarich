defmodule Dawarich.Front.Drainer do
  @moduledoc false

  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def terminate(_reason, _state) do
    with {:ok, bandit} <- Bandit.PhoenixAdapter.bandit_pid(DawarichWeb.Endpoint) do
      ThousandIsland.Server.suspend(bandit)
    end

    :ok
  end
end
