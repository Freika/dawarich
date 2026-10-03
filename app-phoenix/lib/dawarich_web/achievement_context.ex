defmodule DawarichWeb.AchievementContext do
  @moduledoc false
  def clock, do: Application.get_env(:dawarich, :achievement_ui_now, &DateTime.utc_now/0)

  def for_user(user, locale) do
    settings = if(is_map(user.settings), do: user.settings, else: %{})
    clock = clock()
    now = clock.()
    %{locale: locale, settings: settings, now: now, clock: clock}
  end
end
