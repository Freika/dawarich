defmodule Dawarich.Users.DestroyScope do
  @moduledoc false

  def check(repo, id) do
    [[foreign]] =
      repo.query!(
        """
        SELECT EXISTS(SELECT 1 FROM notes n WHERE n.user_id IS DISTINCT FROM $1 AND (
          (n.attachable_type='Trip' AND n.attachable_id IN(SELECT id FROM trips WHERE user_id=$1)) OR
          (n.attachable_type='Place' AND n.attachable_id IN(SELECT id FROM places WHERE user_id=$1)) OR
          (n.attachable_type='Area' AND n.attachable_id IN(SELECT id FROM areas WHERE user_id=$1)) OR
          (n.attachable_type='Visit' AND n.attachable_id IN(SELECT id FROM visits WHERE user_id=$1))))
          OR EXISTS(SELECT 1 FROM shared_links WHERE user_id IS DISTINCT FROM $1 AND resource_type=0
            AND resource_id IN(SELECT id FROM trips WHERE user_id=$1))
          OR EXISTS(SELECT 1 FROM planned_reservations r JOIN trips t ON t.id=r.trip_id
            WHERE t.user_id IS DISTINCT FROM $1 AND r.planned_day_id IN(
              SELECT d.id FROM planned_days d JOIN trips own ON own.id=d.trip_id WHERE own.user_id=$1))
          OR EXISTS(SELECT 1 FROM taggings t LEFT JOIN places p ON t.taggable_type='Place' AND p.id=t.taggable_id
            WHERE t.tag_id IN(SELECT id FROM tags WHERE user_id=$1) AND p.user_id IS DISTINCT FROM $1)
          OR EXISTS(SELECT 1 FROM family_memberships WHERE user_id IS DISTINCT FROM $1
            AND family_id IN(SELECT id FROM families WHERE creator_id=$1))
          OR EXISTS(SELECT 1 FROM family_location_requests WHERE requester_id IS DISTINCT FROM $1
            AND (target_user_id=$1 OR family_id IN(SELECT id FROM families WHERE creator_id=$1)))
        """,
        [id],
        log: false
      ).rows

    if foreign, do: {:cancel, "account deletion blocked by foreign dependents"}, else: :ok
  end
end
