# frozen_string_literal: true

class RecalculateTripsDistance < ActiveRecord::Migration[8.0]
  def up
    Trip.find_each(&:enqueue_calculation_jobs)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
