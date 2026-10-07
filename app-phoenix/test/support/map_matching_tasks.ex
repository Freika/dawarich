defmodule Dawarich.MapMatchingTasks do
  def await!(remaining \\ 1000)
  def await!(0), do: raise("map matching hooks did not finish")

  def await!(remaining) do
    if Process.whereis(Dawarich.Tracks.MapMatching.Tasks) &&
         Task.Supervisor.children(Dawarich.Tracks.MapMatching.Tasks) != [] do
      Process.sleep(5)
      await!(remaining - 1)
    end
  end
end
