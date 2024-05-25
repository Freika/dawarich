# frozen_string_literal: true

class BindExistingPointsToFirstUser < ActiveRecord::Migration[7.1]
  def up
    user = User.first

    points = Point.where(user_id: nil)

    points.update_all(user_id: user.id)

    Rails.logger.info "Bound #{points.count} points to user #{user.email}"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
