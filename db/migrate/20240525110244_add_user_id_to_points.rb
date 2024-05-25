# frozen_string_literal: true

class AddUserIdToPoints < ActiveRecord::Migration[7.1]
  def change
    add_reference :points, :user, foreign_key: true
  end
end
