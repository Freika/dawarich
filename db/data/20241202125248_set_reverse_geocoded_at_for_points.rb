# frozen_string_literal: true

class SetReverseGeocodedAtForPoints < ActiveRecord::Migration[7.2]
  def up
    # rubocop:disable Rails/SkipsModelValidations
    Point.where.not(geodata: {}).update_all(reverse_geocoded_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
