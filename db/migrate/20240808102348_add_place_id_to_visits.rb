# frozen_string_literal: true

class AddPlaceIdToVisits < ActiveRecord::Migration[7.1]
  def change
    add_reference :visits, :place, foreign_key: true
  end
end
