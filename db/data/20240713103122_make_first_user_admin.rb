# frozen_string_literal: true

class MakeFirstUserAdmin < ActiveRecord::Migration[7.1]
  def up
    user = User.first
    user&.update!(admin: true)
  end

  def down
    user = User.first
    user&.update!(admin: false)
  end
end
