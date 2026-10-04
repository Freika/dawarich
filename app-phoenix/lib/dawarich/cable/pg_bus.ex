defmodule Dawarich.Cable.PgBus do
  @moduledoc false
  use GenServer

  def child_spec(opts) do
    %{id: Dawarich.Cable.Bus, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: opts[:name])

  @impl true
  def init(opts), do: {:ok, opts}
end
