defmodule Dawarich.Test.TripPresentationSeeds do
  @moduledoc false
  alias Dawarich.Repo
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  alias Dawarich.Jobs.Ownership
  @now ~U[2026-10-03 10:00:00Z]
  @tables ~w(planned_days planned_stops planned_day_notes planned_reservations planned_accommodations planned_travellers planned_unplanned_places)
  defp value(key, raw) do
    cond do
      is_nil(raw) ->
        nil

      key in ~w(latitude longitude) ->
        Decimal.new(raw)

      key in ~w(date starts_on ends_on) ->
        Date.from_iso8601!(raw)

      key in ~w(created_at updated_at starts_at ends_at noted_at source_synced_at) and
          String.contains?(raw, "T") ->
        raw |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()

      true ->
        raw
    end
  end

  def seed(entry) do
    before = entry["before"]
    actor = before["actor"]

    RailsUser.insert!(%{
      id: actor["id"],
      email: "a8-itinerary-#{actor["id"]}@example.invalid",
      api_key: "a8r-k-#{actor["id"]}",
      settings: actor["settings"],
      changelog_consent: 0
    })

    for source <- before["trip_sources"],
        do:
          Repo.insert_all("trip_sources", [
            Map.merge(Map.new(source, fn {k, v} -> {k, if(k == "status", do: 0, else: v)} end), %{
              "created_at" => DateTime.to_naive(@now),
              "updated_at" => DateTime.to_naive(@now)
            })
          ])

    [trip] = before["trips"]

    TripsSeeds.trip!(%{
      id: trip["id"],
      user_id: actor["id"],
      path: trip["path"],
      name: trip["name"],
      distance: trip["distance"],
      visited_countries: trip["visited_countries"],
      started_at: value("starts_at", trip["started_at"]),
      ended_at: value("ends_at", trip["ended_at"]),
      source_identifier: trip["source_identifier"],
      source_status: if(trip["source_status"] == "stopped", do: 1, else: 0),
      trip_source_id: trip["trip_source_id"],
      source_synced_at: value("source_synced_at", trip["source_synced_at"])
    })

    for table <- @tables do
      rows =
        for row <- before[table], do: Map.new(row, fn {key, raw} -> {key, value(key, raw)} end)

      Repo.insert_all(table, rows)
    end

    for note <- before["notes"] do
      TripsSeeds.note!(%{
        id: note["id"],
        trip_id: trip["id"],
        user_id: actor["id"],
        body: note["body"],
        noted_at: value("noted_at", note["noted_at"])
      })

      Repo.query!("UPDATE notes SET source_digest=$1 WHERE id=$2", [
        note["source_digest"],
        note["id"]
      ])
    end

    for point <- before["points"],
        do:
          TripsSeeds.point!(%{
            id: point["id"],
            user_id: point["user_id"],
            timestamp: point["timestamp"],
            at: point["lonlat"]
          })

    Ownership.put!(Repo, "command:trips.calculate", :oban)
    {Dawarich.Accounts.get(actor["id"]), trip["id"]}
  end
end
