# frozen_string_literal: true

class UpdateImportsPointsCount < ActiveRecord::Migration[8.0]
  def up
    Import.find_each do |import|
      Import::UpdatePointsCountJob.perform_later(import.id)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
