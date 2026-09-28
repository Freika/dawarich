defmodule Dawarich.UserTimeZone do
  @moduledoc false

  alias Dawarich.Repo

  def query!(sql, params, settings) do
    n = length(params)

    Repo.query!(
      """
      WITH z AS (SELECT coalesce(
        (SELECT name FROM pg_timezone_names WHERE name = $#{n + 1}),
        (SELECT name FROM pg_timezone_names WHERE name = $#{n + 2}),
        'UTC') AS name)
      """ <> sql,
      params ++ [zone(settings), System.get_env("TIME_ZONE", "Europe/Berlin")]
    )
  end

  defp zone(%{"timezone" => zone}) when is_binary(zone), do: zone
  defp zone(_settings), do: System.get_env("TIME_ZONE", "UTC")
end
