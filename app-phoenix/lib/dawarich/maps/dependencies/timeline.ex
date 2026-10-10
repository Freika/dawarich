defmodule Dawarich.Maps.Dependencies.Timeline do
  @moduledoc false
  alias Dawarich.Timeline.{DayRows, Days, MonthSummary}

  def feed(user, window, cutoff), do: Days.load(user, window, cutoff)
  def track(user, id), do: DayRows.track(user, id)
  def month(user, month, cutoff, now), do: MonthSummary.build(user, month, cutoff, now)
  def unit(user), do: Days.unit(Dawarich.UserSettings.get(user))
end
