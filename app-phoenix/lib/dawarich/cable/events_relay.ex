defmodule Dawarich.Cable.EventsRelay do
  @moduledoc false
  use GenServer

  require Logger

  alias Dawarich.Cable.TurboEvents

  @poll 1_000
  @backoff 5_000

  def supervisor_spec(opts \\ []) do
    %{
      id: __MODULE__.Supervisor,
      type: :supervisor,
      start:
        {Supervisor, :start_link,
         [
           [{__MODULE__, opts}],
           [
             strategy: :one_for_one,
             max_restarts: 1_000,
             max_seconds: 60,
             name: __MODULE__.Supervisor
           ]
         ]}
    }
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    state = %{
      poll: Keyword.get(opts, :poll, @poll),
      backoff: Keyword.get(opts, :backoff, @backoff)
    }

    {:ok, state, {:continue, :drain}}
  end

  @impl true
  def handle_continue(:drain, state), do: drain(state)

  @impl true
  def handle_info(:drain, state), do: drain(state)

  def next_delay(fun, poll \\ @poll, backoff \\ @backoff) do
    if fun.() == 0, do: poll, else: 0
  rescue
    error ->
      Logger.warning("[Cable] events relay: #{inspect(error.__struct__)}")
      backoff
  catch
    kind, _reason ->
      Logger.warning("[Cable] events relay: #{kind}")
      backoff
  end

  defp drain(state) do
    delay =
      next_delay(
        fn -> TurboEvents.drain(Dawarich.Jobs.repo(), Dawarich.Repo) end,
        state.poll,
        state.backoff
      )

    Process.send_after(self(), :drain, delay)
    {:noreply, state}
  end
end
