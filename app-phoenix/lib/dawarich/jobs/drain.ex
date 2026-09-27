defmodule Dawarich.Jobs.Drain do
  @moduledoc false
  use GenServer

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    {:ok, Keyword.get(opts, :oban, Oban)}
  end

  @impl true
  def terminate(_reason, oban) do
    Oban.pause_all_queues(oban, local_only: true)
  catch
    _kind, _reason -> :ok
  end
end
