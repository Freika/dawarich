defmodule Dawarich.Flights do
  @moduledoc false

  alias Dawarich.{RailsTime, Repo}

  @filter """
  AND ((departure_time BETWEEN (COALESCE($2::text::timestamptz, to_timestamp(0)) AT TIME ZONE 'UTC')
                           AND (COALESCE($3::text::timestamptz, $4::timestamptz) AT TIME ZONE 'UTC'))
       OR (departure_time IS NULL
           AND flight_date BETWEEN COALESCE($2::text::timestamptz, to_timestamp(0))::date
                               AND COALESCE($3::text::timestamptz, $4::timestamptz)::date))
  """

  def term(user_id, filter, now) do
    {where, params} =
      case filter do
        :none -> {"", [user_id]}
        {from, to} -> {@filter, [user_id, from, to, now]}
      end

    rows =
      Repo.query!(
        "SELECT id, from_lon, from_lat, to_lon, to_lat, from_code, to_code, from_name, to_name, airline_name, flight_number, " <>
          "to_char(flight_date, 'YYYY-MM-DD'), #{RailsTime.sql("departure_time", 3)}, #{RailsTime.sql("arrival_time", 3)}, " <>
          "seat, seat_class, distance_km FROM flights WHERE user_id = $1 AND from_lat IS NOT NULL AND from_lon IS NOT NULL " <>
          "AND to_lat IS NOT NULL AND to_lon IS NOT NULL #{where} ORDER BY departure_time LIMIT 2000",
        params
      ).rows

    {:object, [{"type", "FeatureCollection"}, {"features", Enum.map(rows, &feature/1)}]}
  end

  defp feature([
         id,
         from_lon,
         from_lat,
         to_lon,
         to_lat,
         from_code,
         to_code,
         from_name,
         to_name,
         airline,
         number,
         date,
         departure,
         arrival,
         seat,
         seat_class,
         km
       ]) do
    {:object,
     [
       {"type", "Feature"},
       {"geometry",
        {:object,
         [{"type", "LineString"}, {"coordinates", [[from_lon, from_lat], [to_lon, to_lat]]}]}},
       {"properties",
        {:object,
         [
           {"id", id},
           {"from_code", from_code},
           {"to_code", to_code},
           {"from_name", from_name},
           {"to_name", to_name},
           {"airline_name", airline},
           {"flight_number", number},
           {"flight_date", date},
           {"departure_time", departure},
           {"arrival_time", arrival},
           {"seat", seat},
           {"seat_class", seat_class},
           {"distance_km", km}
         ]}}
     ]}
  end
end
