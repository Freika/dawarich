# frozen_string_literal: true

class AddCountryIdToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :points, :country, index: { algorithm: :concurrently }
  end
end
