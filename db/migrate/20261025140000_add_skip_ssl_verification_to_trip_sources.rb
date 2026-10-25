# frozen_string_literal: true

class AddSkipSslVerificationToTripSources < ActiveRecord::Migration[8.1]
  def change
    add_column :trip_sources, :skip_ssl_verification, :boolean, default: false, null: false
  end
end
