defmodule Dawarich.Imports.Trek.Records do
  @moduledoc false
  alias Dawarich.Imports.Trek.{Payload, Itinerary, DayNotes}
  alias Dawarich.Imports.ImportTime

  def synchronize!(ctx, trip, identifier, normalized) do
    digest = Payload.digest(normalized)

    if trip && trip.digest == digest do
      if trip.status == 1,
        do:
          ctx.repo.query!(
            "UPDATE trips SET source_status=0,source_synced_at=$2,updated_at=$2 WHERE id=$1",
            [trip.id, DateTime.to_naive(ctx.now)],
            log: false
          )

      {trip.id, false}
    else
      from =
        ImportTime.parse(normalized["start_date"], ctx.zone, ctx.now, ctx.repo)
        |> DateTime.from_unix!()
        |> DateTime.to_naive()

      day = Payload.date!(normalized["end_date"], "end_date") |> Date.add(1) |> Date.to_iso8601()

      to =
        ImportTime.parse(day, ctx.zone, ctx.now, ctx.repo)
        |> DateTime.from_unix!()
        |> DateTime.to_naive()
        |> NaiveDateTime.add(-1, :microsecond)

      title =
        if Dawarich.Ingest.Ruby.blank?(normalized["title"]),
          do: "Untitled TREK trip",
          else: Dawarich.ReleaseMigrations.Effects.Support.Ruby.to_s(normalized["title"])

      id =
        if trip,
          do: trip.id,
          else:
            Itinerary.insert!(ctx, "trips", %{
              user_id: ctx.user_id,
              trip_source_id: ctx.id,
              source_identifier: to_string(identifier),
              name: title,
              started_at: from,
              ended_at: to
            })

      ctx.repo.query!(
        "UPDATE trips SET name=$2,started_at=$3,ended_at=$4,source_status=0,source_digest=$5,source_snapshot=$6,source_synced_at=$7,updated_at=$7 WHERE id=$1",
        [id, title, from, to, digest, normalized, DateTime.to_naive(ctx.now)],
        log: false
      )

      Itinerary.replace!(ctx, id, normalized)
      DayNotes.sync!(ctx, id, if(trip, do: trip.snapshot), normalized)
      {id, true}
    end
  end

  def find(ctx, identifier) do
    case ctx.repo.query!(
           "SELECT id,source_digest,source_status,source_snapshot FROM trips WHERE trip_source_id=$1 AND user_id=$2 AND source_identifier=$3 FOR UPDATE",
           [ctx.id, ctx.user_id, to_string(identifier)],
           log: false
         ).rows do
      [[id, digest, status, snapshot]] ->
        %{id: id, digest: digest, status: status, snapshot: snapshot}

      [] ->
        nil
    end
  end

  def calculate!(ctx, id, force) do
    [[started, path, distance, countries]] =
      ctx.repo.query!(
        "SELECT started_at,path IS NULL,distance,visited_countries FROM trips WHERE id=$1",
        [id],
        log: false
      ).rows

    if NaiveDateTime.compare(started, DateTime.to_naive(ctx.now)) != :gt and
         (force or path or is_nil(distance) or countries in [nil, %{}, []]) do
      unit = get_in(ctx.settings, ["maps", "distance_unit"]) || "km"
      payload = %{"trip_id" => id, "distance_unit" => unit}
      owner = Dawarich.Tracks.Owner.lock(ctx.repo, "command:trips.calculate")

      if owner == :oban do
        ctx.repo.query!(
          "INSERT INTO job_outbox(event_id,command_type,command_version,payload,aggregate_id,dedupe_key,metadata,scheduled_at) VALUES($1,'trips.calculate',1,$2,$3,$4,$5,now()) ON CONFLICT DO NOTHING",
          [
            Ecto.UUID.dump!(Ecto.UUID.generate()),
            payload,
            id,
            to_string(id),
            %{"producer" => "Trip#enqueue_calculation_jobs"}
          ],
          log: false
        )
      else
        Dawarich.RailsCommands.insert!(
          ctx.repo,
          "trips.calculate",
          Map.put(payload, "user_id", ctx.user_id)
        )
      end
    end
  end
end
