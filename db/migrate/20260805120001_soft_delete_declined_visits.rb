# frozen_string_literal: true

# Declined visits stop being a user-facing state: the flattened timeline has
# no review verbs, so historical declines become soft-deleted tombstones —
# hidden from every reader, still visible to Visits::Creator's dedup so the
# detector never re-suggests them.
class SoftDeleteDeclinedVisits < ActiveRecord::Migration[8.0]
  # Batched UPDATEs only bound lock time if each batch commits on its own;
  # inside the default wrapping transaction they'd hold one giant lock.
  disable_ddl_transaction!

  DECLINED = 2
  BATCH_SIZE = 10_000

  def up
    # Keyset, not LIMIT-on-a-predicate: nothing indexes
    # `status = 2 AND deleted_at IS NULL`, so a re-filtered batch would
    # re-scan the heap from block 0 every iteration and skip the rows it
    # just wrote — quadratic in the number of declined visits.
    last_id = 0

    loop do
      ids = connection.select_values(<<~SQL.squish)
        SELECT id FROM visits
        WHERE id > #{last_id} AND status = #{DECLINED}
        ORDER BY id
        LIMIT #{BATCH_SIZE}
      SQL
      break if ids.empty?

      connection.update(<<~SQL.squish)
        UPDATE visits SET deleted_at = NOW()
        WHERE id IN (#{ids.join(',')}) AND deleted_at IS NULL
      SQL

      last_id = ids.last
    end
  end

  def down
    # Tombstoned declines keep status = declined, so this is reversible.
    execute(<<~SQL.squish)
      UPDATE visits SET deleted_at = NULL WHERE status = #{DECLINED}
    SQL
  end
end
