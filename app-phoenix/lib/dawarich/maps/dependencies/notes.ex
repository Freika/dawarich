defmodule Dawarich.Maps.Dependencies.Notes do
  @moduledoc false
  alias Dawarich.NotesApi.{Read, Write}

  def list(owner, type, id, zone),
    do: Read.index(owner, %{"attachable_type" => type, "attachable_id" => id}, zone)

  def create(owner, attrs, zone, now), do: Write.create(owner, attrs, zone, now)
end
