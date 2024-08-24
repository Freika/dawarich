# frozen_string_literal: true

class AddCounterCacheToImports < ActiveRecord::Migration[7.1]
  def up
    Import.find_each do |import|
      Import.reset_counters(import.id, :points)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
