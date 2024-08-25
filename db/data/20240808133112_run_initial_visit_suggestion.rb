# frozen_string_literal: true

class RunInitialVisitSuggestion < ActiveRecord::Migration[7.1]
  def up
    start_at = 30.years.ago
    end_at = Time.current

    VisitSuggestingJob.perform_later(start_at:, end_at:)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
