defmodule DawarichWeb.Api.Params do
  @moduledoc false
  defdelegate year(arg1), to: Dawarich.Input.Params
  defdelegate unit(arg1, arg2), to: Dawarich.Input.Params
  defdelegate min_minutes(arg1), to: Dawarich.Input.Params
  defdelegate timestamp(arg1), to: Dawarich.Input.Params
  defdelegate flight_filter(arg1, arg2), to: Dawarich.Input.Params
  defdelegate missing(arg1, arg2), to: Dawarich.Input.Params
  defdelegate if_modified_since(arg1), to: Dawarich.Input.Params
  defdelegate http_date(arg1), to: Dawarich.Input.Params
  defdelegate coordinates(arg1, arg2), to: Dawarich.Input.Params
  defdelegate count(arg1, arg2), to: Dawarich.Input.Params
  defdelegate date(arg1), to: Dawarich.Input.Params
  defdelegate text(arg1), to: Dawarich.Input.Params
end
