# frozen_string_literal: true

class AddVisitIdToPoints < ActiveRecord::Migration[7.1]
  def change
    add_reference :points, :visit, foreign_key: true
  end
end
