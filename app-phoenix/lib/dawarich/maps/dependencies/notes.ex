defmodule Dawarich.Maps.Dependencies.Notes do
  @moduledoc false
  alias Dawarich.NotesApi.{Read, Write}

  def list(owner, type, id, zone),
    do: Read.index(owner, %{"attachable_type" => type, "attachable_id" => id}, zone)

  def create(owner, attrs, zone, now), do: Write.create(owner, attrs, zone, now)

  def trip_change(scope, action, trip_id, note_id, attrs) do
    Dawarich.Maps.with_actor(scope, fn actor ->
      Dawarich.Trips.WebNotes.run(Dawarich.Repo, action, actor, trip_id, note_id, attrs, %{
        now: DateTime.utc_now(),
        locale: scope.locale
      })
    end)
  end
end
