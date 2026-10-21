defmodule DawarichWeb.StatsFormat do
  @moduledoc false
  defdelegate unit(arg1), to: Dawarich.Formatting.StatsFormat
  defdelegate convert(arg1, arg2), to: Dawarich.Formatting.StatsFormat
  defdelegate rounded(arg1, arg2), to: Dawarich.Formatting.StatsFormat
  defdelegate distance(arg1, arg2, arg3), to: Dawarich.Formatting.StatsFormat
  defdelegate header_color(arg1), to: Dawarich.Formatting.StatsFormat
  defdelegate sample_header_color(arg1, arg2, arg3), to: Dawarich.Formatting.StatsFormat
  defdelegate month_icon(arg1), to: Dawarich.Formatting.StatsFormat
  defdelegate month_color(arg1), to: Dawarich.Formatting.StatsFormat
  defdelegate month_background(arg1), to: Dawarich.Formatting.StatsFormat
  defdelegate year_map_path(arg1), to: Dawarich.Formatting.StatsFormat
  defdelegate active_days(arg1), to: Dawarich.Formatting.StatsFormat
  defdelegate than_average(arg1, arg2, arg3), to: Dawarich.Formatting.StatsFormat
  defdelegate than_previous_active_days(arg1, arg2, arg3), to: Dawarich.Formatting.StatsFormat
  defdelegate than_previous_countries(arg1, arg2, arg3), to: Dawarich.Formatting.StatsFormat
  defdelegate peak(arg1), to: Dawarich.Formatting.StatsFormat
  defdelegate peak_text(arg1, arg2, arg3, arg4, arg5), to: Dawarich.Formatting.StatsFormat
  defdelegate peak_href(arg1), to: Dawarich.Formatting.StatsFormat
  defdelegate quietest_week(arg1, arg2, arg3, arg4), to: Dawarich.Formatting.StatsFormat
  defdelegate city_progress(arg1, arg2), to: Dawarich.Formatting.StatsFormat
  defdelegate progress_color(arg1), to: Dawarich.Formatting.StatsFormat
  defdelegate upgrade_url(arg1, arg2, arg3, arg4, arg5), to: Dawarich.Formatting.StatsFormat
end
