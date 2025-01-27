# frozen_string_literal: true

class CreateTracksFromPoints < ActiveRecord::Migration[8.0]
  def up
    # Get all users to process their points separately
    User.find_each do |user|
      Tracks::CreatePathJob.perform_later(user.id)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
