defmodule Dawarich.MapMatchingTasks do
  def await_dispatch!(remaining \\ 1000)
  def await_dispatch!(0), do: raise("map matching dispatch did not finish")

  def await_dispatch!(remaining) do
    if GenServer.call(Dawarich.Tracks.MapMatching.Deferred, :busy?) do
      Process.sleep(5)
      await_dispatch!(remaining - 1)
    end
  end

  def await!(remaining \\ 1000)
  def await!(0), do: raise("map matching hooks did not finish")

  def await!(remaining) do
    dispatching = GenServer.call(Dawarich.Tracks.MapMatching.Deferred, :busy?)
    tasks = Process.whereis(Dawarich.Tracks.MapMatching.Tasks)

    if dispatching or
         (tasks && Task.Supervisor.children(tasks) != []) do
      Process.sleep(5)
      await!(remaining - 1)
    end
  end
end
