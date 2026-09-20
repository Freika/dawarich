# frozen_string_literal: true

class Places::OrphanCleanupJob < ApplicationJob
  queue_as :places
  BATCH = 500

  # Drains the given user's orphan suggested places. Every place carries a
  # user_id (NOT NULL since 20260815100001), so there is no ownerless pass.
  def perform(user_id)
    return unless User.exists?(id: user_id)

    drain("user=#{user_id}", user_victims_sql, victim_binds(user_id))
  end

  private

  def drain(scope, sql, binds)
    total = 0
    loop do
      deleted = delete_batch(sql, binds)
      break if deleted.zero?

      total += deleted
      Rails.logger.info("[OrphanCleanup] #{scope} batch=#{deleted} total=#{total}")
      sleep 0.05
    end
  end

  def delete_batch(sql, binds)
    conn = Place.connection
    deleted = 0

    conn.transaction do
      victim_ids = conn.exec_query(sql, 'OrphanCleanup victims', binds).rows.map { |r| r[0] }
      break if victim_ids.empty?

      # Victims are only referenced by hidden visits (tombstones/declines);
      # detach those so the FK allows the delete. Dedup survives via each
      # visit's own points (Visit#center fallback).
      Visit.where(place_id: victim_ids).update_all(place_id: nil)
      PlaceVisit.where(place_id: victim_ids).delete_all
      deleted = Place.where(id: victim_ids).delete_all
    end

    deleted
  end

  def user_victims_sql
    victims_sql('p.user_id = $1')
  end

  def victims_sql(user_predicate)
    # Join only ACTIVE visits: a place kept alive solely by tombstoned or
    # declined visits is still an orphan for the user-facing catalogue.
    <<~SQL.squish
      SELECT p.id
      FROM places p
      LEFT JOIN visits v   ON v.place_id = p.id
                          AND v.deleted_at IS NULL
                          AND v.status <> #{Visit.statuses[:declined]}
      LEFT JOIN taggings t ON t.taggable_id = p.id AND t.taggable_type = 'Place'
      WHERE #{user_predicate}
        AND p.source = #{Place.sources[:photon]}
        AND (p.note IS NULL OR p.note = '')
        AND v.id IS NULL
        AND t.id IS NULL
      LIMIT #{BATCH}
    SQL
  end

  def victim_binds(user_id)
    [ActiveRecord::Relation::QueryAttribute.new('user_id', user_id, ActiveRecord::Type::Integer.new)]
  end
end
