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

  def delete!(repo, ids, nil), do: delete!(repo, ids)

  def delete!(repo, ids, user) do
    for sql <- [
          "UPDATE visits SET place_id=NULL WHERE place_id=ANY($1) AND user_id=$2",
          "DELETE FROM place_visits pv USING visits v WHERE pv.visit_id=v.id AND pv.place_id=ANY($1) AND v.user_id=$2",
          "DELETE FROM taggings g USING tags t WHERE g.tag_id=t.id AND g.taggable_type='Place' AND g.taggable_id=ANY($1) AND t.user_id=$2",
          "DELETE FROM notes WHERE attachable_type='Place' AND attachable_id=ANY($1) AND user_id=$2",
          "DELETE FROM places WHERE id=ANY($1) AND user_id=$2"
        ],
        do: repo.query!(sql, [ids, user], log: false)
  end
end
