# frozen_string_literal: true

class EnablePostgisExtension < ActiveRecord::Migration[8.0]
  def change
    enable_extension 'postgis'
  end
end
