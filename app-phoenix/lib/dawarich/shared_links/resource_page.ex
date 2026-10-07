defmodule Dawarich.SharedLinks.ResourcePage do
  @moduledoc false
  alias Dawarich.{Accounts, CountryNames, Repo, TripSettings, UserTimeZone}
  alias Dawarich.SharedApi.{Photos, Privacy}

  def load(link) do
    settings = Accounts.settings(link.user_id)
    {:ok, display} = TripSettings.read(settings)
    zone = UserTimeZone.iana(Repo, settings)
    data = resource(link)
    started = UserTimeZone.local(settings, data.started)
    ended = UserTimeZone.local(settings, data.ended)

    Map.merge(data, %{
      settings: display,
      zone: zone,
      started_at: started,
      ended_at: ended,
      duration: duration(data.started, data.ended, zone),
      flags: CountryNames.table(),
      countries: if(is_list(data[:countries]), do: Enum.sort(data.countries), else: []),
      days: days(link, data, settings, zone),
      family: Dawarich.SharedLinks.FamilyAudience.family_only?(link)
    })
  end

  defp resource(%{type: "trip"} = link) do
    [[name, started, ended, distance, countries, description]] =
      Repo.query!(
        "SELECT t.name,t.started_at,t.ended_at,t.distance,t.visited_countries," <>
          "(SELECT body FROM action_text_rich_texts WHERE record_type='Trip' AND record_id=t.id AND name='description') " <>
          "FROM trips t WHERE t.id=$1 AND t.user_id=$2",
        [link.resource_id, link.user_id],
        log: false
      ).rows

    %{
      name: name,
      started: started,
      ended: ended,
      distance: distance,
      countries: countries,
      description: if(link.settings["show_description"] != false, do: description(description))
    }
  end

  defp resource(%{type: "track"} = link) do
    [[started, ended, distance, duration, speed, gain, loss, mode]] =
      Repo.query!(
        "SELECT start_at,end_at,distance,duration,avg_speed,elevation_gain,elevation_loss,dominant_mode " <>
          "FROM tracks WHERE id=$1 AND user_id=$2",
        [link.resource_id, link.user_id],
        log: false
      ).rows

    %{
      started: started,
      ended: ended,
      distance: distance,
      track_duration: duration,
      speed: speed,
      gain: gain,
      loss: loss,
      mode: mode
    }
  end

  defp description(body) do
    case Dawarich.Trips.RichContent.read(body) do
      {:ok, rendered} -> rendered
      :rails -> Dawarich.HtmlSanitizer.sanitize(body || "")
    end
  end

  defp days(%{type: "trip", settings: flags} = link, data, settings, zone) do
    if flags["show_days"] == false do
      []
    else
      stats = day_stats(link, data, zone)

      notes =
        if flags["show_day_notes"] == true,
          do: Dawarich.TripPage.day_notes(link.resource_id),
          else: %{}

      photos = Enum.map(Photos.gallery(link), fn {:object, fields} -> Map.new(fields) end)

      for date <-
            Date.range(
              NaiveDateTime.to_date(UserTimeZone.local(settings, data.started).local),
              NaiveDateTime.to_date(UserTimeZone.local(settings, data.ended).local)
            ) do
        %{
          date: date,
          stats: stats[date],
          note: notes[date],
          photos: Enum.filter(photos, &(photo_date(&1, zone) == date))
        }
      end
    end
  end

  defp days(_, _, _, _), do: []

  defp day_stats(link, data, zone) do
    Repo.query!(
      "SELECT (to_timestamp(p.timestamp) AT TIME ZONE $4)::date,min(p.timestamp),max(p.timestamp)," <>
        "COALESCE(ST_Length(ST_MakeLine(p.lonlat::geometry ORDER BY p.timestamp)::geography),0) " <>
        "FROM points p WHERE p.user_id=$1 AND p.anomaly IS NOT TRUE AND p.timestamp BETWEEN extract(epoch FROM $2::timestamp)::bigint " <>
        "AND extract(epoch FROM $3::timestamp)::bigint AND #{Privacy.outside("p.lonlat")} GROUP BY 1",
      [link.user_id, data.started, data.ended, zone],
      log: false
    ).rows
    |> Map.new(fn [date, first, last, distance] ->
      {date, %{first: time(first, zone), last: time(last, zone), distance: distance}}
    end)
  end

  defp time(epoch, zone) do
    [[at]] =
      Repo.query!("SELECT to_timestamp($1) AT TIME ZONE $2", [epoch, zone], log: false).rows

    at
  end

  defp photo_date(photo, zone) do
    raw = photo["taken_at"] || photo["capturedAt"] || photo["localDateTime"]

    if epoch = Dawarich.Imports.ImportTime.parse(raw, zone, DateTime.utc_now()),
      do: NaiveDateTime.to_date(time(epoch, zone))
  end

  defp duration(first, last, zone) do
    span = Dawarich.TripDays.local_span(first, last, zone)

    {parts, _} =
      Dawarich.TripDays.duration_parts(
        span.started_local,
        span.ended_local,
        span.previous_month_days
      )

    parts
  end
end
