defmodule Dawarich.AirTrail.Flights do
  @moduledoc false

  alias Dawarich.Jobs.Processed
  alias Dawarich.Mail.ExploreFeatures

  @handler "imports.airtrail_flights"
  @earth_radius_km 6371.0
  @false_values [nil, "", false, 0, "0", "f", "F", "false", "FALSE", "off", "OFF"]
  @scope "jobs.air_trail.import_flights_job."
  @iso ~S"^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?)?(Z|[+-]\d{2}(:?\d{2})?)?$"

  @months_before ~S"""
  SELECT
    COALESCE((SELECT jsonb_agg(DISTINCT jsonb_build_array(EXTRACT(YEAR FROM flight_date)::integer,
                                                          EXTRACT(MONTH FROM flight_date)::integer))
              FROM flights WHERE user_id = $1 AND flight_date IS NOT NULL), '[]'::jsonb),
    COALESCE((SELECT jsonb_agg(floor(EXTRACT(EPOCH FROM departure_time))::bigint)
              FROM flights WHERE user_id = $1 AND flight_date IS NULL AND departure_time IS NOT NULL), '[]'::jsonb)
  """

  @upsert ~S"""
  WITH input AS (
    SELECT DISTINCT ON ((e.f->>'id')::integer) e.f, d.km, r.raw
    FROM jsonb_array_elements($2::text::jsonb) WITH ORDINALITY AS e(f, i)
    JOIN unnest($3::float8[]) WITH ORDINALITY AS d(km, i) USING (i)
    JOIN jsonb_array_elements($5::jsonb) WITH ORDINALITY AS r(raw, i) USING (i)
    ORDER BY (e.f->>'id')::integer, e.i DESC
  ), mapped AS (
    SELECT
      (f->>'id')::integer AS external_id,
      CASE WHEN f->>'date' ~ '^\d{4}-\d{2}-\d{2}' THEN left(f->>'date', 10)::date END AS flight_date,
      COALESCE(f->>'datePrecision', 'day') AS date_precision,
      COALESCE(NULLIF(btrim(f->>'departure'), ''), NULLIF(btrim(f->>'takeoffActual'), ''),
               NULLIF(btrim(f->>'takeoffScheduled'), ''), NULLIF(btrim(f->>'departureScheduled'), '')) AS dep,
      COALESCE(NULLIF(btrim(f->>'arrival'), ''), NULLIF(btrim(f->>'landingActual'), ''),
               NULLIF(btrim(f->>'landingScheduled'), ''), NULLIF(btrim(f->>'arrivalScheduled'), '')) AS arr,
      f->'from'->>'icao' AS from_code, f->'from'->>'name' AS from_name,
      CASE WHEN jsonb_typeof(f->'from'->'lat') = 'number' THEN (f->'from'->>'lat')::float8 END AS from_lat,
      CASE WHEN jsonb_typeof(f->'from'->'lon') = 'number' THEN (f->'from'->>'lon')::float8 END AS from_lon,
      f->'to'->>'icao' AS to_code, f->'to'->>'name' AS to_name,
      CASE WHEN jsonb_typeof(f->'to'->'lat') = 'number' THEN (f->'to'->>'lat')::float8 END AS to_lat,
      CASE WHEN jsonb_typeof(f->'to'->'lon') = 'number' THEN (f->'to'->>'lon')::float8 END AS to_lon,
      f->'airline'->>'name' AS airline_name, f->'airline'->>'iata' AS airline_iata,
      f->'aircraft'->>'name' AS aircraft_name, f->>'aircraftReg' AS aircraft_reg,
      f->>'flightNumber' AS flight_number,
      COALESCE(f->'seats'->0->>'seat', f->'seats'->0->>'seatNumber') AS seat,
      f->'seats'->0->>'seatClass' AS seat_class,
      f->>'note' AS note, km AS distance_km, raw
    FROM input
  )
  INSERT INTO flights (user_id, external_id, flight_date, date_precision, departure_time, arrival_time,
    from_code, from_name, from_lat, from_lon, to_code, to_name, to_lat, to_lon, airline_name, airline_iata,
    aircraft_name, aircraft_reg, flight_number, seat, seat_class, note, distance_km, raw, created_at, updated_at)
  SELECT $1, external_id, flight_date, date_precision,
    CASE WHEN dep ~ $4 THEN dep::timestamptz AT TIME ZONE 'UTC' END,
    CASE WHEN arr ~ $4 THEN arr::timestamptz AT TIME ZONE 'UTC' END,
    from_code, from_name, from_lat, from_lon, to_code, to_name, to_lat, to_lon, airline_name, airline_iata,
    aircraft_name, aircraft_reg, flight_number, seat, seat_class, note, distance_km, raw,
    now() AT TIME ZONE 'UTC', now() AT TIME ZONE 'UTC'
  FROM mapped
  ON CONFLICT (user_id, external_id) DO UPDATE SET
    flight_date = EXCLUDED.flight_date, date_precision = EXCLUDED.date_precision,
    departure_time = EXCLUDED.departure_time, arrival_time = EXCLUDED.arrival_time,
    from_code = EXCLUDED.from_code, from_name = EXCLUDED.from_name, from_lat = EXCLUDED.from_lat,
    from_lon = EXCLUDED.from_lon, to_code = EXCLUDED.to_code, to_name = EXCLUDED.to_name,
    to_lat = EXCLUDED.to_lat, to_lon = EXCLUDED.to_lon, airline_name = EXCLUDED.airline_name,
    airline_iata = EXCLUDED.airline_iata, aircraft_name = EXCLUDED.aircraft_name,
    aircraft_reg = EXCLUDED.aircraft_reg, flight_number = EXCLUDED.flight_number, seat = EXCLUDED.seat,
    seat_class = EXCLUDED.seat_class, note = EXCLUDED.note, distance_km = EXCLUDED.distance_km,
    raw = EXCLUDED.raw, updated_at = EXCLUDED.updated_at
  WHERE (flights.flight_date, flights.date_precision, flights.departure_time, flights.arrival_time,
         flights.from_code, flights.from_name, flights.from_lat, flights.from_lon, flights.to_code,
         flights.to_name, flights.to_lat, flights.to_lon, flights.airline_name, flights.airline_iata,
         flights.aircraft_name, flights.aircraft_reg, flights.flight_number, flights.seat,
         flights.seat_class, flights.note, flights.distance_km, flights.raw)
    IS DISTINCT FROM
        (EXCLUDED.flight_date, EXCLUDED.date_precision, EXCLUDED.departure_time, EXCLUDED.arrival_time,
         EXCLUDED.from_code, EXCLUDED.from_name, EXCLUDED.from_lat, EXCLUDED.from_lon, EXCLUDED.to_code,
         EXCLUDED.to_name, EXCLUDED.to_lat, EXCLUDED.to_lon, EXCLUDED.airline_name, EXCLUDED.airline_iata,
         EXCLUDED.aircraft_name, EXCLUDED.aircraft_reg, EXCLUDED.flight_number, EXCLUDED.seat,
         EXCLUDED.seat_class, EXCLUDED.note, EXCLUDED.distance_km, EXCLUDED.raw)
  """

  @delete_unseen ~S"""
  DELETE FROM flights WHERE user_id = $1 AND external_id NOT IN (
    SELECT id::integer FROM jsonb_array_elements_text($2::jsonb) AS e(id) WHERE id IS NOT NULL)
  """

  @synced_at ~S"""
  UPDATE users SET settings = jsonb_set(settings, '{airtrail_last_synced_at}',
      to_jsonb(to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SS') ||
               CASE WHEN to_char(now(), 'TZH:TZM') = '+00:00' THEN 'Z' ELSE to_char(now(), 'TZH:TZM') END)),
    updated_at = now() AT TIME ZONE 'UTC'
  WHERE id = $1
  """

  def source(repo, user_id) do
    with %{"airtrail_url" => url, "airtrail_api_key" => key} = settings
         when is_binary(url) and is_binary(key) <- settings(repo, user_id),
         true <- String.trim(url) != "" and String.trim(key) != "" do
      %{
        url: url,
        api_key: key,
        skip_ssl_verification: settings["airtrail_skip_ssl_verification"] not in @false_values
      }
    else
      _ -> nil
    end
  end

  def store(repo, user_id, flights, event_id, time_zone) do
    distances = Enum.map(flights, &distance_km/1)

    {:ok, :ok} =
      repo.transaction(fn ->
        repo.query!("SELECT set_config('TimeZone', $1, true)", [time_zone], log: false)
        %{rows: [[months, epochs]]} = repo.query!(@months_before, [user_id], log: false)

        repo.query!(@upsert, [user_id, Jason.encode!(flights), distances, @iso, flights],
          log: false
        )

        repo.query!(@delete_unseen, [user_id, Enum.map(flights, & &1["id"])], log: false)
        repo.query!(@synced_at, [user_id], log: false)

        :ok =
          Dawarich.RailsCommands.insert!(repo, "airtrail_stats", %{
            "user_id" => user_id,
            "months" => months,
            "departure_epochs" => epochs
          })

        Processed.mark!(repo, event_id, @handler)
      end)

    :ok
  rescue
    error in Postgrex.Error -> {:error, {:store_failed, error.postgres[:code]}}
  end

  def fail!(repo, user_id, message) do
    {:ok, _} =
      repo.transaction(fn ->
        case settings_row(repo, user_id) do
          {:ok, settings} ->
            locale = ExploreFeatures.locale(settings || %{}, nil)

            content =
              text!(locale, "your_airtrail_flight_sync_failed_with_error_message_check_your", %{
                "message" => message
              })

            Dawarich.Notifications.create!(
              repo,
              user_id,
              :error,
              text!(locale, "airtrail_sync_failed"),
              content
            )

          :missing ->
            :ok
        end
      end)

    {:error, :airtrail_sync_failed}
  end

  def distance_km(flight) do
    from = if is_map(flight["from"]), do: flight["from"], else: %{}
    to = if is_map(flight["to"]), do: flight["to"], else: %{}
    coordinates = [from["lat"], from["lon"], to["lat"], to["lon"]]

    if Enum.all?(coordinates, &is_number/1), do: haversine(coordinates)
  end

  defp haversine([lat1, lon1, lat2, lon2]) do
    rad = fn degrees -> degrees * :math.pi() / 180 end
    dlat = rad.(lat2 - lat1)
    dlon = rad.(lon2 - lon1)

    a =
      :math.pow(:math.sin(dlat / 2), 2) +
        :math.cos(rad.(lat1)) * :math.cos(rad.(lat2)) * :math.pow(:math.sin(dlon / 2), 2)

    Dawarich.RubyFloat.round(
      @earth_radius_km * 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a)),
      1
    )
  end

  defp settings(repo, user_id) do
    case settings_row(repo, user_id) do
      {:ok, settings} when is_map(settings) -> settings
      _ -> nil
    end
  end

  defp settings_row(repo, user_id) do
    case repo.query!("SELECT settings FROM users WHERE id = $1 AND deleted_at IS NULL", [user_id],
           log: false
         ).rows do
      [[settings]] -> {:ok, settings}
      [] -> :missing
    end
  end

  defp text!(locale, key, bindings \\ %{}) do
    {:ok, text} = Dawarich.I18n.t(locale, @scope <> key, bindings)
    text
  end
end
