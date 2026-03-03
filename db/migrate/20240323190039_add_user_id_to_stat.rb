# frozen_string_literal: true

class AddUserIdToStat < ActiveRecord::Migration[7.1]
  def change
    add_reference :stats, :user, null: false, foreign_key: true
  end
end
