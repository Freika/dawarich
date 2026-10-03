defmodule Dawarich.Stats.MonthQueries do
  @moduledoc false

  def window(year, month) do
    first = Date.new!(year, month, 1)
    start = first |> DateTime.new!(~T[00:00:00]) |> DateTime.to_unix()
    finish = first |> Date.end_of_month() |> DateTime.new!(~T[23:59:59]) |> DateTime.to_unix()
    {start - 172_800, finish + 172_800}
  end
end
