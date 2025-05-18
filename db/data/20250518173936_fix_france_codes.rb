# frozen_string_literal: true

class FixFranceCodes < ActiveRecord::Migration[8.0]
  def up
    Country.find_by(name: 'France')&.update(iso_a2: 'FR', iso_a3: 'FRA')
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
