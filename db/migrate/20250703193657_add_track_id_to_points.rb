# frozen_string_literal: true

class AddTrackIdToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :points, :track, index: { algorithm: :concurrently }
  end
end
