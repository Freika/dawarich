# frozen_string_literal: true

class AddDeviceIdToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :points, :device, null: true, index: { algorithm: :concurrently }
  end
end
