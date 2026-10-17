defmodule Dawarich.Areas.CleanupScope do
  @moduledoc false

  def ensure!(repo, owner, area, visits) do
    foreign? =
      repo.query!(
        """
        SELECT EXISTS(SELECT 1 FROM visits WHERE area_id=$2 AND user_id IS DISTINCT FROM $1)
          OR EXISTS(SELECT 1 FROM points WHERE visit_id=ANY($3) AND user_id IS DISTINCT FROM $1)
          OR EXISTS(SELECT 1 FROM notes WHERE user_id IS DISTINCT FROM $1 AND (
            (attachable_type='Area' AND attachable_id=$2) OR
            (attachable_type='Visit' AND attachable_id=ANY($3))))
          OR EXISTS(SELECT 1 FROM place_visits pv JOIN places p ON p.id=pv.place_id
            WHERE pv.visit_id=ANY($3) AND p.user_id IS DISTINCT FROM $1)
          OR EXISTS(SELECT 1 FROM visits v JOIN places p ON p.id=v.place_id
            WHERE v.id=ANY($3) AND p.user_id IS DISTINCT FROM $1)
        """,
        [owner, area, visits],
        log: false
      ).rows == [[true]]

    if foreign?, do: repo.rollback(:foreign_area_dependency)
    :ok
  end
end
