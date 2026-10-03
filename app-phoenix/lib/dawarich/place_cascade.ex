defmodule Dawarich.PlaceCascade do
  @moduledoc false

  @deletes [
    "UPDATE visits SET place_id = NULL WHERE place_id = ANY($1)",
    "DELETE FROM place_visits WHERE place_id = ANY($1)",
    "DELETE FROM taggings WHERE taggable_type = 'Place' AND taggable_id = ANY($1)",
    "DELETE FROM notes WHERE attachable_type = 'Place' AND attachable_id = ANY($1)",
    "DELETE FROM places WHERE id = ANY($1)"
  ]

  def delete!(repo, ids), do: Enum.each(@deletes, &repo.query!(&1, [ids], log: false))
end
