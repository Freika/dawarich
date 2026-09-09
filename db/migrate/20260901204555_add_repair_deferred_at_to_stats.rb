# frozen_string_literal: true

class AddRepairDeferredAtToStats < ActiveRecord::Migration[8.0]
  def up
    return if column_exists?(:stats, :repair_deferred_at)

    add_column :stats, :repair_deferred_at, :datetime
  end

  def down
    return unless column_exists?(:stats, :repair_deferred_at)

    remove_column :stats, :repair_deferred_at
  end
end
