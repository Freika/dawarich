# frozen_string_literal: true

# Declined visits stop being a user-facing state: the flattened timeline has
# no review verbs, so historical declines become soft-deleted tombstones —
# hidden from every reader, still visible to Visits::Creator's dedup so the
# detector never re-suggests them.
class SoftDeleteDeclinedVisits < ActiveRecord::Migration[8.0]
  DECLINED = 2

  def up
    execute(<<~SQL.squish)
      UPDATE visits SET deleted_at = NOW()
      WHERE status = #{DECLINED} AND deleted_at IS NULL
    SQL
  end

  def down
    # Tombstoned declines keep status = declined, so this is reversible.
    execute(<<~SQL.squish)
      UPDATE visits SET deleted_at = NULL WHERE status = #{DECLINED}
    SQL
  end
end
