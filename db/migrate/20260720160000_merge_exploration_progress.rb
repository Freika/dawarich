# frozen_string_literal: true

class MergeExplorationProgress < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:achievement_progresses)

    Achievements::MigrateExplorationState.new.call
  end

  def down; end
end
