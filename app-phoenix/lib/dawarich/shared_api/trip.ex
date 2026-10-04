defmodule Dawarich.SharedApi.Trip do
  @moduledoc false

  alias Dawarich.{Distance, RailsTime, Repo, RubyFloat, UserTimeZone}

  def show(link, zone \\ UserTimeZone.name(%{"timezone" => ""}))

  def show(%{type: "trip"} = link, zone) do
    RailsTime.with_zone(zone, fn ->
      sql =
        "SELECT t.name, #{RailsTime.sql("t.started_at", 3)}, #{RailsTime.sql("t.ended_at", 3)}, " <>
          "t.distance, u.settings FROM trips t JOIN users u ON u.id = t.user_id " <>
          "WHERE t.id = $1 AND t.user_id = $2"

      case Repo.query!(sql, [link.resource_id, link.user_id]).rows do
        [[name, started, ended, distance, settings]] ->
          fields = [{"name", name}, {"started_at", started}, {"ended_at", ended}]
          stats(fields, link.settings, distance, settings)

        [] ->
          {:error, 410, "gone"}
      end
    end)
  end

  def show(_link, _zone), do: {:replay, "shared trip resource type"}

  defp stats(fields, %{"show_stats" => true}, distance, settings) when not is_nil(distance) do
    unit = get_in(settings || %{}, ["maps", "distance_unit"]) || "km"

    if Distance.unit?(unit),
      do:
        {:ok,
         {:object,
          fields ++
            [
              {"distance", RubyFloat.round(Distance.convert(distance, unit))},
              {"distance_unit", unit}
            ]}},
      else: {:replay, "shared distance unit"}
  end

  defp stats(fields, _flags, _distance, _settings), do: {:ok, {:object, fields}}
end
