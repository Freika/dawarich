defmodule DawarichWeb.TripRequest do
  @moduledoc false
  import DawarichWeb.A8Request, only: [member: 4, nested?: 3, root?: 2, scalar_map?: 1]
  @trip ~w(name started_at ended_at description)
  @note ~w(date body)

  def target(["trips"]), do: {:trip_create, ["POST"], "POST"}

  def target(["trips", id]),
    do: member(id, :trip, ~w(PATCH PUT DELETE POST), ~w(PATCH PUT DELETE))

  def target(["trips", id, "recalculate"]), do: member(id, :trip_recalculate, ["POST"], "POST")
  def target(["trips", id, "export"]), do: member(id, :trip_export, ["POST"], "POST")
  def target(["trips", trip_id, "notes"]), do: member(trip_id, :note_create, ["POST"], "POST")

  def target(["trips", trip_id, "notes", id]) do
    with {_, _, _} <- member(trip_id, :note, [], []),
         do: member(id, :note, ~w(PATCH PUT DELETE POST), ~w(PATCH PUT DELETE))
  end

  def target(_), do: nil

  def action(:trip, "DELETE"), do: :trip_destroy
  def action(:trip, _), do: :trip_update
  def action(:note, "DELETE"), do: :note_destroy
  def action(:note, _), do: :note_update
  def action(action, _method), do: action

  def fields?(action, params) when action in [:trip_create, :trip_update],
    do: nested?(params, "trip", @trip)

  def fields?(action, params) when action in [:note_create, :note_update],
    do: nested?(params, "note", @note)

  def fields?(:trip_export, params), do: root?(params, ~w(file_format)) and scalar_map?(params)

  def fields?(action, params) when action in [:trip_destroy, :trip_recalculate, :note_destroy],
    do: root?(params, [])

  def fields?(_, _), do: false

  def query_keys(:trip_export), do: ~w(file_format)
  def query_keys(_), do: []
  def repeated_keys, do: ["visit_ids[]"]
end
