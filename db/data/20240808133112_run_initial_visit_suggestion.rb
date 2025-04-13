# frozen_string_literal: true

class RunInitialVisitSuggestion < ActiveRecord::Migration[7.1]
  def up
    start_at = 30.years.ago
    end_at = Time.current

    User.find_each do |user|
      VisitSuggestingJob.perform_later(user_id: user.id, start_at:, end_at:)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
