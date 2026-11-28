# frozen_string_literal: true

class AddSkipSslVerificationToTripSources < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:trip_sources, :skip_ssl_verification)

    add_column :trip_sources, :skip_ssl_verification, :boolean, default: false, null: false
  end

  def down
    remove_column :trip_sources, :skip_ssl_verification if column_exists?(:trip_sources, :skip_ssl_verification)
  end
end
