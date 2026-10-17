defmodule DawarichWeb.HumanDatetime do
  @moduledoc false
  defdelegate human_datetime(arg1), to: Dawarich.Formatting.HumanDatetime
  defdelegate human_datetime_with_seconds(arg1), to: Dawarich.Formatting.HumanDatetime
  defdelegate text(arg1, arg2), to: Dawarich.Formatting.HumanDatetime
  defdelegate text(arg1, arg2, arg3), to: Dawarich.Formatting.HumanDatetime
  defdelegate iso8601(arg1), to: Dawarich.Formatting.HumanDatetime
end
