defmodule Dawarich.Trips.PlanRead do
  @moduledoc false
  @trip ~w(id user_id name started_at ended_at source_identifier source_status source_synced_at trip_source_id)a
  @source ~w(id provider base_url status last_synced_at)a
  @day ~w(id date position title notes)a
  @stop ~w(id planned_day_id position name address category starts_at ends_at duration_minutes transport_mode latitude longitude notes)a
  @note ~w(id planned_day_id position noted_at body)a
  @reservation ~w(id trip_id planned_day_id title reservation_type starts_at ends_at location status notes)a
  @stay ~w(id name address starts_on ends_on check_in_at check_out_at latitude longitude notes)a
  @traveller ~w(id name owner)a
  @loose ~w(id position name address category starts_at ends_at duration_minutes transport_mode latitude longitude notes)a
  @in_days "planned_day_id IN (SELECT id FROM planned_days WHERE trip_id=$1)"

  def load(repo, user_id, trip_id) do
    case rows(repo, "trips", @trip, "id=$1 AND user_id=$2", [trip_id, user_id], "id") do
      [trip] ->
        days = rows(repo, "planned_days", @day, "trip_id=$1", [trip_id], "date")

        stops =
          rows(repo, "planned_stops", @stop, @in_days, [trip_id], "planned_day_id, position")

        notes =
          rows(repo, "planned_day_notes", @note, @in_days, [trip_id], "planned_day_id, position")

        reservations =
          rows(
            repo,
            "planned_reservations",
            @reservation,
            "trip_id=$1 OR " <> @in_days,
            [trip_id],
            "id"
          )

        {:ok,
         %{
           trip: trip,
           source: source(repo, trip.trip_source_id),
           days:
             Enum.map(days, fn day ->
               Map.merge(day, %{
                 stops: child_rows(stops, day.id),
                 day_notes: child_rows(notes, day.id),
                 reservations: child_rows(reservations, day.id)
               })
             end),
           reservations: Enum.filter(reservations, &(&1.trip_id == trip_id)),
           accommodations:
             rows(repo, "planned_accommodations", @stay, "trip_id=$1", [trip_id], "id"),
           travellers:
             rows(repo, "planned_travellers", @traveller, "trip_id=$1", [trip_id], "id"),
           unplanned_places:
             rows(repo, "planned_unplanned_places", @loose, "trip_id=$1", [trip_id], "position")
         }}

      [] ->
        :not_found
    end
  end

  defp source(_repo, nil), do: nil

  defp source(repo, id),
    do: rows(repo, "trip_sources", @source, "id=$1", [id], "id") |> List.first()

  defp child_rows(rows, id), do: Enum.filter(rows, &(&1.planned_day_id == id))

  defp rows(repo, table, fields, where, params, order) do
    repo.query!(
      "SELECT #{Enum.join(fields, ", ")} FROM #{table} WHERE #{where} ORDER BY #{order}",
      params,
      log: false
    ).rows
    |> Enum.map(&(Enum.zip(fields, &1) |> Map.new()))
  end
end
