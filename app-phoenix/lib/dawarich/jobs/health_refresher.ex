defmodule Dawarich.Jobs.HealthRefresher do
  @moduledoc false
  use GenServer
  require Logger

  @interval 15_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    refresh = Keyword.get(opts, :refresh, fn -> Dawarich.Jobs.Health.refresh(opts) end)
    send(self(), :refresh)
    {:ok, refresh}
  end

  @impl true
  def handle_info(:refresh, refresh) do
    run(refresh)
    Process.send_after(self(), :refresh, @interval)
    {:noreply, refresh}
  end

  defp run(refresh) do
    refresh.()
  rescue
    error -> Logger.warning("[JobHealth] refresh failed: #{inspect(error.__struct__)}")
  catch
    kind, _ -> Logger.warning("[JobHealth] refresh failed: #{kind}")
  end
end
