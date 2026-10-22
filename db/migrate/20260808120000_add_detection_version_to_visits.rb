# frozen_string_literal: true

class AddDetectionVersionToVisits < ActiveRecord::Migration[8.0]
  def change
    add_column :visits, :detection_version, :smallint, if_not_exists: true
  end
end
