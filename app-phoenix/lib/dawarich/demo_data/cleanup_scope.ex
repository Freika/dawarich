defmodule Dawarich.DemoData.CleanupScope do
  @moduledoc false

  @checks [
    """
    SELECT EXISTS(SELECT 1 FROM points p WHERE p.user_id<>$1 AND (
      p.visit_id IN (SELECT id FROM visits WHERE user_id=$1 AND demo=true) OR
      p.track_id IN (SELECT id FROM tracks WHERE user_id=$1 AND demo=true)))
    """,
    """
    SELECT EXISTS(SELECT 1 FROM notes n WHERE n.user_id<>$1 AND (
      (n.attachable_type='Visit' AND n.attachable_id IN (SELECT id FROM visits WHERE user_id=$1 AND demo=true)) OR
      (n.attachable_type='Place' AND n.attachable_id IN (SELECT id FROM places WHERE user_id=$1 AND demo=true)) OR
      (n.attachable_type='Trip' AND n.attachable_id IN (SELECT id FROM trips WHERE user_id=$1 AND demo=true))))
    """,
    """
    SELECT EXISTS(SELECT 1 FROM shared_links s WHERE s.user_id<>$1 AND (
      (s.resource_type=0 AND s.resource_id IN (SELECT id FROM trips WHERE user_id=$1 AND demo=true)) OR
      (s.resource_type=1 AND s.resource_id IN (SELECT id FROM tracks WHERE user_id=$1 AND demo=true))))
    """,
    """
    SELECT EXISTS(SELECT 1 FROM visits v WHERE v.user_id<>$1 AND v.demo=true
      AND v.place_id IN (SELECT id FROM places WHERE user_id=$1 AND demo=true))
    """,
    """
    SELECT EXISTS(SELECT 1 FROM place_visits pv
      JOIN visits v ON v.id=pv.visit_id JOIN places p ON p.id=pv.place_id
      WHERE (v.user_id=$1 AND v.demo=true AND p.user_id<>$1) OR
        (p.user_id=$1 AND p.demo=true AND v.user_id<>$1))
    """,
    """
    SELECT EXISTS(SELECT 1 FROM taggings g JOIN tags t ON t.id=g.tag_id
      LEFT JOIN places p ON g.taggable_type='Place' AND p.id=g.taggable_id
      WHERE (t.user_id=$1 AND t.demo=true AND p.user_id IS DISTINCT FROM $1) OR
        (p.user_id=$1 AND p.demo=true AND t.user_id<>$1))
    """
  ]

  def ensure!(repo, user) do
    for table <- ~w(visits trips tracks tags places) do
      repo.query!(
        "SELECT id FROM #{table} WHERE user_id=$1 AND demo=true ORDER BY id FOR UPDATE",
        [user],
        log: false
      )
    end

    if Enum.any?(@checks, &(repo.query!(&1, [user], log: false).rows == [[true]])),
      do: repo.rollback(:foreign_demo_dependency)

    :ok
  end
end
