# frozen_string_literal: true

class AddStateIdToCities < ActiveRecord::Migration[8.0]
  def change
    add_reference :cities, :state, foreign_key: true
  end
end
