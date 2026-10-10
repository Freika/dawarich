defmodule Dawarich.Maps.Dependencies.Trip do
  @moduledoc false
  alias Dawarich.{Maps, TripPage}

  def config(scope, id, opts \\ []) do
    with {:ok, data} <- read(scope, id, opts), do: {:ok, data["config"]}
  end

  def read(scope, id, opts \\ [])

  def read(scope, id, opts) when is_integer(id) and id > 0 do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    Maps.with_actor(
      scope,
      fn user ->
        case TripPage.load(user, id, now) do
          {:ok, page} -> {:ok, project(page)}
          _ -> {:error, :not_found}
        end
      end,
      now: now
    )
  end

  def read(_, _, _), do: {:error, :invalid}

  defp project(page) do
    config = %{
      "tripId" => page.id,
      "title" => page.name,
      "range" => %{
        "startAt" => DawarichWeb.HumanDatetime.iso8601(page.started_at),
        "endAt" => DawarichWeb.HumanDatetime.iso8601(page.ended_at),
        "timezone" => page.iana
      },
      "routeOptions" => %{
        "distanceThresholdMeters" => page.settings.meters,
        "timeThresholdMinutes" => page.settings.minutes
      },
      "styleName" => page.settings.style,
      "photosEnabled" => page.settings.photos,
      "flightsEnabled" => page.settings.airtrail,
      "planEnabled" => page.plan_on_map,
      "mapState" => to_string(page.map_state)
    }

    %{
      "config" => config,
      "path" => decode(page.path_json, []),
      "deviceWindows" => decode(page.windows_json, []),
      "plan" => decode(page.plan_json, nil)
    }
  end

  defp decode(value, fallback) when value in [nil, ""], do: fallback
  defp decode(value, _fallback), do: Jason.decode!(value)
end
