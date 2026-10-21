defmodule Dawarich.Sharing.ResourceWindow do
  @moduledoc false
  alias Dawarich.{Accounts, Repo, UserTimeZone}
  alias Dawarich.SharedApi.Privacy

  def params(params) when is_map(params) do
    if Enum.all?(params, fn {key, value} ->
         key in ~w(cursor) and (is_nil(value) or (is_binary(value) and byte_size(value) <= 10))
       end), do: :ok, else: {:error, :invalid_input}
  end

  def params(_), do: {:error, :invalid_input}

  def load(%{type: type} = link, params, opts) when type in ["trip", "track"] do
    with :ok <- params(params),
         {:ok, data} <- header(link) do
      settings = Accounts.settings(link.user_id)
      zone = UserTimeZone.iana(Repo, settings)
      started = UserTimeZone.local(settings, data.started).local
      ended = UserTimeZone.local(settings, data.ended).local
      first = NaiveDateTime.to_date(started)
      last = NaiveDateTime.to_date(ended)

      with {:ok, cursor} <- cursor(params["cursor"], first, last) do
        dates = Date.range(cursor, last) |> Enum.take(31)

        days =
          if type == "trip" and link.settings["show_days"] != false,
            do: days(link, dates, zone, data),
            else: []

        photos = if link.settings["show_photos"] == true, do: photos(link, opts), else: []

        span = Dawarich.TripDays.local_span(data.started, data.ended, zone)

        {duration, _} =
          Dawarich.TripDays.duration_parts(
            span.started_local,
            span.ended_local,
            span.previous_month_days
          )

        {:ok,
         %{
           name: data.name,
           unit: Dawarich.Analytics.Period.unit(settings),
           duration: duration,
           track_duration: if(link.settings["show_stats"] == true, do: data[:track_duration]),
           speed: if(link.settings["show_stats"] == true, do: data[:speed]),
           gain: if(link.settings["show_stats"] == true, do: data[:gain]),
           loss: if(link.settings["show_stats"] == true, do: data[:loss]),
           mode: if(link.settings["show_stats"] == true, do: data[:mode]),
           started_at: started,
           ended_at: ended,
           distance: if(link.settings["show_stats"] == true, do: data.distance),
           countries: if(link.settings["show_stats"] == true, do: data.countries, else: []),
           zone: zone,
           days: days,
           photos: photos,
           next_cursor:
             if(days != [] and Date.compare(List.last(dates), last) == :lt,
               do: List.last(dates) |> Date.add(1) |> Date.to_iso8601()
             ),
           description:
             if(link.settings["show_description"] != false, do: description(data.body), else: nil)
         }}
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def load(%{type: type, settings: settings}, params, _) when type in ["live", "timeline"] do
    with :ok <- params(params),
         do:
           {:ok,
            %{
              days: [],
              photos: [],
              description: nil,
              next_cursor: nil,
              range: Map.take(settings || %{}, ~w(start_date end_date))
            }}
  end

  def load(_, _, _), do: {:error, :not_found}

  defp header(%{type: "trip"} = link) do
    case rows(
           "SELECT t.name,t.started_at,t.ended_at,t.distance,t.visited_countries,(SELECT body FROM action_text_rich_texts WHERE record_type='Trip' AND record_id=t.id AND name='description' LIMIT 1) FROM trips t WHERE t.id=$1 AND t.user_id=$2",
           [link.resource_id, link.user_id]
         ) do
      [[name, started, ended, distance, countries, body]] ->
        {:ok,
         %{
           name: name,
           started: started,
           ended: ended,
           distance: distance,
           countries: if(is_list(countries), do: Enum.filter(countries, &is_binary/1), else: []),
           body: body
         }}

      _ ->
        {:error, :not_found}
    end
  end

  defp header(%{type: "track"} = link) do
    case rows(
           "SELECT start_at,end_at,distance,duration,avg_speed,elevation_gain,elevation_loss,dominant_mode FROM tracks WHERE id=$1 AND user_id=$2",
           [
             link.resource_id,
             link.user_id
           ]
         ) do
      [[started, ended, distance, duration, speed, gain, loss, mode]] ->
        {:ok,
         %{
           name: nil,
           track_duration: duration,
           speed: speed,
           gain: gain,
           loss: loss,
           mode: mode,
           started: started,
           ended: ended,
           distance: distance,
           countries: [],
           body: nil
         }}

      _ ->
        {:error, :not_found}
    end
  end

  defp cursor(nil, first, _), do: {:ok, first}

  defp cursor(raw, first, last) do
    with {:ok, date} <- Date.from_iso8601(raw),
         true <- Date.compare(date, first) != :lt and Date.compare(date, last) != :gt,
         do: {:ok, date},
         else: (_ -> {:error, :invalid_input})
  end

  defp days(link, dates, zone, data) do
    stats =
      rows(
        "SELECT (to_timestamp(p.timestamp) AT TIME ZONE $4)::date,min(to_timestamp(p.timestamp) AT TIME ZONE $4),max(to_timestamp(p.timestamp) AT TIME ZONE $4),COALESCE(ST_Length(ST_MakeLine(p.lonlat::geometry ORDER BY p.timestamp)::geography),0) FROM points p WHERE p.user_id=$1 AND p.anomaly IS NOT TRUE AND p.timestamp BETWEEN extract(epoch FROM $2::timestamp)::bigint AND extract(epoch FROM $3::timestamp)::bigint AND (to_timestamp(p.timestamp) AT TIME ZONE $4)::date BETWEEN $5 AND $6 AND #{Privacy.outside("p.lonlat")} GROUP BY 1",
        [link.user_id, data.started, data.ended, zone, hd(dates), List.last(dates)]
      )
      |> Map.new(fn [date, first, last, distance] ->
        {date, %{first: first, last: last, distance: distance}}
      end)

    notes =
      if link.settings["show_day_notes"] == true,
        do:
          rows(
            "SELECT n.noted_at::date,n.body FROM notes n WHERE n.attachable_type='Trip' AND n.attachable_id=$1 AND n.user_id=$2 AND n.noted_at::date BETWEEN $3 AND $4",
            [link.resource_id, link.user_id, hd(dates), List.last(dates)]
          )
          |> Map.new(fn [date, body] -> {date, body} end),
        else: %{}

    Enum.map(dates, &%{date: &1, stats: stats[&1], note: notes[&1]})
  end

  defp photos(link, opts) do
    reader = Keyword.get(opts, :photos, &Dawarich.SharedApi.Photos.response(&1, :photos))

    case reader.(link) do
      {:ok, photos} ->
        photos |> Enum.take(100) |> Enum.map(fn {:object, fields} -> Map.new(fields) end)

      _ ->
        []
    end
  end

  defp description(nil), do: nil

  defp description(body) do
    case Dawarich.Trips.Description.render(body) do
      {:ok, html} -> html
      _ -> :unavailable
    end
  end

  defp rows(sql, args), do: Repo.query!(sql, args, log: false).rows
end
