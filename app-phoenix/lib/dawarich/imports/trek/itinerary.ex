defmodule Dawarich.Imports.Trek.Itinerary do
  @moduledoc false
  alias Dawarich.Imports.{ImportTime, ZonePeriod}
  alias Dawarich.Imports.Trek.Payload
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def replace!(ctx, trip, payload) do
    repo = ctx.repo

    for table <- ~w(planned_stops planned_day_notes) do
      repo.query!(
        "DELETE FROM #{table} WHERE planned_day_id IN (SELECT id FROM planned_days WHERE trip_id=$1)",
        [trip],
        log: false
      )
    end

    for table <-
          ~w(planned_reservations planned_days planned_accommodations planned_travellers planned_unplanned_places) do
      repo.query!("DELETE FROM #{table} WHERE trip_id=$1", [trip], log: false)
    end

    for day <- Payload.collection!(payload, "days") do
      date = Payload.date!(day["date"], "day date")

      id =
        insert!(ctx, "planned_days", %{
          trip_id: trip,
          date: date,
          position: Payload.integer!(day["day_number"], "day number"),
          title: text(day["title"]),
          notes: text(day["notes"])
        })

      day
      |> Payload.collection!("places")
      |> Enum.with_index()
      |> Enum.each(fn {stop, index} ->
        insert!(ctx, "planned_stops", Map.put(stop(ctx, stop, index), :planned_day_id, id))
      end)

      day
      |> Payload.collection!("day_notes")
      |> Enum.with_index()
      |> Enum.each(fn {note, index} ->
        insert!(ctx, "planned_day_notes", %{
          planned_day_id: id,
          position: index,
          noted_at: local_time(ctx, note["time"]),
          body: text(note["text"])
        })
      end)

      for reservation <- Payload.collection!(day, "reservations"),
          do: reservation!(ctx, trip, id, date, reservation)
    end

    for reservation <- Payload.collection!(payload, "unscheduled_reservations"),
        do: reservation!(ctx, trip, nil, nil, reservation)

    for item <- Payload.collection!(payload, "accommodations") do
      insert!(ctx, "planned_accommodations", %{
        trip_id: trip,
        name: present(item["name"], "Accommodation"),
        address: text(item["address"]),
        latitude: decimal(item["lat"]),
        longitude: decimal(item["lng"]),
        starts_on: date(item["start_date"]),
        ends_on: date(item["end_date"]),
        check_in_at: local_time(ctx, item["check_in"]),
        check_out_at: local_time(ctx, item["check_out"]),
        notes: text(item["notes"])
      })
    end

    for item <- Payload.collection!(payload, "travellers"),
        do:
          insert!(ctx, "planned_travellers", %{
            trip_id: trip,
            name: text(item["name"]),
            owner: item["owner"] == true
          })

    payload
    |> Payload.collection!("unplanned_places")
    |> Enum.with_index()
    |> Enum.each(fn {place, index} ->
      insert!(ctx, "planned_unplanned_places", Map.put(stop(ctx, place, index), :trip_id, trip))
    end)

    :ok
  end

  def insert!(ctx, table, attrs) do
    attrs =
      Map.merge(attrs, %{
        created_at: DateTime.to_naive(ctx.now),
        updated_at: DateTime.to_naive(ctx.now)
      })

    {1, [%{id: id}]} = ctx.repo.insert_all(table, [attrs], returning: [:id])
    id
  end

  def local_time(ctx, value) do
    case datetime(ctx, value) do
      nil ->
        nil

      time ->
        ZonePeriod.local_now(ctx.zone, DateTime.from_naive!(time, "Etc/UTC"))
        |> NaiveDateTime.to_time()
        |> Time.to_iso8601()
        |> String.slice(0, 8)
    end
  end

  def datetime(_ctx, nil), do: nil

  def datetime(ctx, value) do
    unless Ruby.blank?(value) do
      case ImportTime.parse(Ruby.to_s(value), ctx.zone, ctx.now, ctx.repo) do
        nil -> nil
        epoch -> epoch |> DateTime.from_unix!() |> DateTime.to_naive()
      end
    end
  rescue
    _ -> nil
  end

  defp reservation!(ctx, trip, day, date, item) do
    insert!(ctx, "planned_reservations", %{
      trip_id: trip,
      planned_day_id: day,
      reservation_type: text(item["type"]),
      title: present(item["title"], "Reservation"),
      location: text(item["location"]),
      starts_at: reservation_time(ctx, item["time"], date),
      ends_at: reservation_time(ctx, item["end_time"], date),
      status: text(item["status"]),
      notes: text(item["notes"])
    })
  end

  defp reservation_time(ctx, value, date) do
    value =
      if date && is_binary(value) && Regex.match?(~r/\A\d{1,2}:\d{2}(?::\d{2})?\z/, value),
        do: "#{date} #{value}",
        else: value

    datetime(ctx, value)
  end

  defp stop(ctx, item, index) do
    %{
      position: index,
      name: text(item["name"]),
      address: text(item["address"]),
      latitude: decimal(item["lat"]),
      longitude: decimal(item["lng"]),
      starts_at: local_time(ctx, item["time"]),
      ends_at: local_time(ctx, item["end_time"]),
      duration_minutes:
        if(item["duration_minutes"] != nil,
          do: Payload.integer!(item["duration_minutes"], "duration")
        ),
      category: text(item["category"]),
      transport_mode: text(item["transport_mode"]),
      notes: text(item["notes"])
    }
  end

  defp date(nil), do: nil
  defp date(value), do: Payload.date!(value, "date")
  defp decimal(nil), do: nil
  defp decimal(value), do: value |> Ruby.to_s() |> Decimal.new() |> Decimal.round(6, :half_up)
  defp text(nil), do: nil
  defp text(value), do: Ruby.to_s(value)
  defp present(value, default), do: if(Ruby.blank?(value), do: default, else: text(value))
end
